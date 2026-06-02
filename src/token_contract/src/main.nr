pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract Token {
    // aztec library
    use aztec::{
        capsules::CapsuleArray,
        macros::{
            events::event,
            functions::{authorize_once, external, initializer, internal, only_self, view},
            storage::storage,
        },
        messages::message_delivery::MessageDelivery,
        protocol::{address::AztecAddress, traits::{FromField, ToField}},
        state_vars::{Map, Owned, PublicImmutable, PublicMutable, StateVariable},
    };
    // note library
    use uint_note::{PartialUintNote, UintNote};
    // compression library
    use compressed_string::FieldCompressedString;
    // private balance library
    use balance_set::BalanceSet;

    // gas-optimized max notes for initial transfer call
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    // max notes transfer for recursive transfer call if initial max notes are exceeded
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    // Sentinel address used in Transfer events to represent the private side of a balance change.
    // sha224sum 'PRIVATE_ADDRESS'
    global PRIVATE_ADDRESS_MAGIC_VALUE: AztecAddress =
        AztecAddress::from_field(0x1ea7e01501975545617c2e694d931cb576b691a4a867fed81ebd3264);

    #[event]
    struct Transfer {
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
    }

    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param private_balances The private balances of the token
    /// @param total_supply The total supply of the token
    /// @param public_balances The public balances of the token
    /// @param minter The account permissioned to mint the token
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<Field, Owned<BalanceSet<Context>, Context>, Context>,
        total_supply: PublicMutable<u128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
    }

    // Default label used when the caller does not choose one. A label makes a private balance
    // non-fungible by tracing its origin (e.g. the mint it came from).
    global NULL_LABEL: Field = 0;

    // Capsule base slots used to pass the caller's chosen label(s) from the PXE into private
    // execution. These are PXE-local, scoped per address, and persist across the recursive
    // folding frames of `_subtract_balance` (unlike ephemeral arrays, which are frame-isolated).
    // The values are spaced far apart so the `CapsuleArray` element slots never collide.
    // Ordered FIFO queue of labels to spend from, scoped to the account being debited.
    global SPEND_LABELS_BASE_SLOT: Field = 0x10000000;
    // Single label to credit when receiving/minting, scoped to the account being credited.
    global RECEIVE_LABEL_SLOT: Field = 0x20000000;
    // Single label to query, scoped to the owner being queried.
    global QUERY_LABEL_SLOT: Field = 0x30000000;

    /// @notice Initializes the token with an initial supply
    /// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param initial_supply The initial supply of the token
    /// @param to The address to mint the initial supply to
    #[external("public")]
    #[initializer]
    fn constructor_with_initial_supply(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        initial_supply: u128,
        to: AztecAddress,
    ) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.decimals.initialize(decimals);

        self.internal._mint_to_public(to, initial_supply);
    }

    /// @notice Initializes the token with a minter
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param minter The address of the minter
    #[external("public")]
    #[initializer]
    fn constructor_with_minter(name: str<31>, symbol: str<31>, decimals: u8, minter: AztecAddress) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.decimals.initialize(decimals);

        self.storage.minter.initialize(minter);
    }

    /** ==========================================================
    * ========================= PRIVATE =========================
    * ======================================================== */

    /// @notice Transfer tokens from private balance to public balance
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        self.enqueue_self.increase_public_balance_internal(to, amount);
    }

    /// @notice Transfer tokens from private balance to public balance and initializes a commitment
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, enqueues a public call, and returns a partial note.
    ///      The sender will be used as the completer for the initialized partial note.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    /// @return commitment The partial note utilized for the transfer commitment (privacy entrance)
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_public_with_commitment(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) -> Field {
        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        self.enqueue_self.increase_public_balance_internal(to, amount);

        // Only the sender will be able to complete the partial note
        let completer = self.msg_sender();
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        commitment.to_field()
    }

    /// @notice Transfer tokens from private balance to another private balance
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and sends a note to the recipient
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        self.internal._increase_private_balance(to, amount);
    }

    /// @notice Transfer tokens from a private balance to the recipient commitment, which must be already initialized.
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call.
    ///      The `msg_sender` must be the completer of the partial note.
    /// @param from The address of the sender
    /// @param commitment The partial note representing the commitment (privacy entrance that the recipient shares with the sender)
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        let completer = self.msg_sender();
        PartialUintNote::from_field(commitment).complete_from_private(
            self.context,
            completer,
            self.storage.private_balances.at(NULL_LABEL).get_storage_slot(),
            amount,
        );
    }

    /// @notice Transfer tokens from public balance to private balance
    /// @dev Enqueues a public call to decrease account balance and emits a new note with balance difference
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        self.enqueue_self.decrease_public_balance_internal(from, amount);

        self.internal._increase_private_balance(to, amount);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @dev Returns a partial note that can be used to execute transfers/mints
    /// @param to The address of the recipient
    /// @param completer The address allowed to complete the partial note
    /// @return commitment The partial note initialized for the transfer/mint commitment
    #[external("private")]
    fn initialize_transfer_commitment(to: AztecAddress, completer: AztecAddress) -> Field {
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        commitment.to_field()
    }

    /// @notice Recursively subtracts balance from private balance
    /// @dev Used to subtract private balances that exceed the max notes limit, or to continue
    ///      spending under the next label in the caller's queue
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    #[external("private")]
    #[only_self]
    fn recurse_subtract_balance_internal(account: AztecAddress, amount: u128) {
        self.internal._subtract_balance(account, amount, RECURSIVE_TRANSFER_CALL_MAX_NOTES);
    }

    /** ==========================================================
    * ========================= PUBLIC ==========================
    * ======================================================== */

    /// @notice Transfers tokens from public balance to public balance
    /// @dev Public call to decrease account balance and a public call to increase recipient balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn transfer_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._decrease_public_balance(from, amount);
        self.internal._increase_public_balance(to, amount);

        self.emit(Transfer { from, to, amount });
    }

    /// @notice Finalizes a transfer of token `amount` from public balance of `from` to a commitment of `to`
    /// @dev The transfer must be prepared by calling `initialize_transfer_commitment` first and the resulting
    /// `commitment` must be passed as an argument to this function.
    /// @dev The sender will be used as the completer for the partial note.
    /// @param from The address of the sender
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn transfer_public_to_commitment(
        from: AztecAddress,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._decrease_public_balance(from, amount);

        let completer = self.msg_sender();
        self.internal._increase_commitment_balance(
            PartialUintNote::from_field(commitment),
            completer,
            amount,
        );

        self.emit(Transfer { from, to: PRIVATE_ADDRESS_MAGIC_VALUE, amount });
    }

    /// @notice Increases the public balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[external("public")]
    #[only_self]
    fn increase_public_balance_internal(to: AztecAddress, amount: u128) {
        self.internal._increase_public_balance(to, amount);

        self.emit(Transfer { from: PRIVATE_ADDRESS_MAGIC_VALUE, to, amount });
    }

    /// @notice Decreases the public balance of `from` by `amount`
    /// @param from The address of the sender
    /// @param amount The amount of tokens to decrease the balance by
    #[external("public")]
    #[only_self]
    fn decrease_public_balance_internal(from: AztecAddress, amount: u128) {
        self.internal._decrease_public_balance(from, amount);

        self.emit(Transfer { from, to: PRIVATE_ADDRESS_MAGIC_VALUE, amount });
    }

    /** ==========================================================
    * ====================== VIEW FUNCTIONS =====================
    * ======================================================== */

    /// @notice Returns the public balance of `owner`
    /// @param owner The address of the owner
    /// @return The balance of the public balance of `owner`
    #[external("public")]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> u128 {
        self.storage.public_balances.at(owner).read()
    }

    /// @notice Returns the total supply of the token
    /// @return The total supply of the token
    #[external("public")]
    #[view]
    fn total_supply() -> u128 {
        self.storage.total_supply.read()
    }

    /// @notice Returns the name of the token
    /// @return The name of the token
    #[external("public")]
    #[view]
    fn name() -> FieldCompressedString {
        self.storage.name.read()
    }

    /// @notice Returns the symbol of the token
    /// @return The symbol of the token
    #[external("public")]
    #[view]
    fn symbol() -> FieldCompressedString {
        self.storage.symbol.read()
    }

    /// @notice Returns the decimals of the token
    /// @return The decimals of the token
    #[external("public")]
    #[view]
    fn decimals() -> u8 {
        self.storage.decimals.read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    /// @notice Returns the private balance of an account under the caller's chosen label
    /// @dev The label to query is read from a capsule (defaulting to `NULL_LABEL`), so the caller
    ///      can inspect any individual label balance without changing this method's signature.
    /// @param owner The address to query
    /// @return The private balance of the address under the chosen label
    #[external("utility")]
    unconstrained fn balance_of_private(owner: AztecAddress) -> u128 {
        let contract_address = self.context.this_address();
        let label = _read_label(contract_address, owner, QUERY_LABEL_SLOT);
        self.storage.private_balances.at(label).at(owner).balance_of()
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    /// @notice Mints tokens to a private balance
    /// @dev Mints tokens to a private balance and enqueues a public call to increase the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[external("private")]
    fn mint_to_private(to: AztecAddress, amount: u128) {
        _validate_minter(self.msg_sender(), self.storage.minter.read());

        self.internal._mint_to_private(to, amount);
    }

    /// @notice Mints tokens to an address publicly
    /// @dev Increases the public balance of `to` by `amount` and the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[external("public")]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        _validate_minter(self.msg_sender(), self.storage.minter.read());

        self.internal._mint_to_public(to, amount);
    }

    /// @notice Finalizes a mint to a commitment
    /// @dev Finalizes a mint to a commitment and updates the total supply
    /// @param commitment The partial note representing the mint commitment (privacy entrance)
    /// @param amount The amount of tokens to mint
    #[external("public")]
    fn mint_to_commitment(commitment: Field, amount: u128) {
        let completer = self.msg_sender();
        _validate_minter(completer, self.storage.minter.read());
        self.internal._increase_total_supply(amount);
        self.internal._increase_commitment_balance(
            PartialUintNote::from_field(commitment),
            completer,
            amount,
        );

        self.emit(Transfer { from: AztecAddress::zero(), to: PRIVATE_ADDRESS_MAGIC_VALUE, amount });
    }

    /// @notice Internal function to increase the total supply by `amount`
    /// @param amount The amount to increase the total supply by
    #[external("public")]
    #[only_self]
    fn increase_total_supply_internal(amount: u128) {
        self.internal._increase_total_supply(amount);

        self.emit(Transfer { from: AztecAddress::zero(), to: PRIVATE_ADDRESS_MAGIC_VALUE, amount });
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns tokens from a private balance
    /// @dev Burns tokens from a private balance and enqueues a public call to update the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn burn_private(from: AztecAddress, amount: u128, _nonce: Field) {
        self.internal._burn_private(from, amount);
    }

    /// @notice Burns tokens from a public balance
    /// @dev Burns tokens from a public balance and updates the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn burn_public(from: AztecAddress, amount: u128, _nonce: Field) {
        self.internal._burn_public(from, amount);
    }

    /// @notice Decreases the total supply by `amount`
    /// @param amount The amount of tokens to decrease the total supply by
    #[external("public")]
    #[only_self]
    fn decrease_total_supply_internal(amount: u128) {
        self.internal._decrease_total_supply(amount);

        self.emit(Transfer { from: PRIVATE_ADDRESS_MAGIC_VALUE, to: AztecAddress::zero(), amount });
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// @notice Validates that the caller is the minter
    /// @param sender The address of the caller
    /// @param minter The address of the authorized minter
    #[contract_library_method]
    fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }

    /// @notice Pops the next label to spend from for `account` off the caller-provided queue
    /// @dev Unconstrained: the label is the caller's free choice of which sub-balance to spend
    ///      from, and only selects a storage slot of the caller's own notes. Backed by a capsule
    ///      array so it persists across the recursive `_subtract_balance` frames. Returns
    ///      `NULL_LABEL` once the queue is empty.
    /// @param contract The address of this contract (the only contract allowed to read its capsules)
    /// @param account The account whose spend-label queue is being consumed
    /// @return The next label to spend from
    #[contract_library_method]
    unconstrained fn _pop_spend_label(
        contract_address: AztecAddress,
        account: AztecAddress,
    ) -> Field {
        let queue: CapsuleArray<Field> =
            CapsuleArray::at(contract_address, SPEND_LABELS_BASE_SLOT, account);
        if queue.len() == 0 {
            NULL_LABEL
        } else {
            let label = queue.get(0);
            queue.remove(0);
            label
        }
    }

    /// @notice Reads the single label stored by the caller at `slot`, scoped to `scope`
    /// @dev Unconstrained: the label is the caller's free choice and only selects a storage slot.
    ///      Returns `NULL_LABEL` when nothing was stored.
    /// @param contract The address of this contract (the only contract allowed to read its capsules)
    /// @param scope The address the label is scoped to (recipient when receiving, owner when querying)
    /// @param slot The capsule slot holding the label
    /// @return The chosen label
    #[contract_library_method]
    unconstrained fn _read_label(
        contract_address: AztecAddress,
        scope: AztecAddress,
        slot: Field,
    ) -> Field {
        let stored: Option<Field> = aztec::oracle::capsules::load(contract_address, slot, scope);
        stored.unwrap_or(NULL_LABEL)
    }

    /// @notice Decreases the private balance of `account` by `amount` and emits a private balance note with the change to account
    /// @param account The address of the account to decrease the balance of
    /// @param amount The amount of tokens to decrease the balance by
    /// @param max_notes The maximum number of notes to process in a single call
    #[internal("private")]
    fn _decrease_private_balance(account: AztecAddress, amount: u128, max_notes: u32) {
        // Subtracts `amount` from the private balance of `account`, spending across as many labels
        // as needed. The change (if any) is re-deposited into the label it was spent from inside
        // `_subtract_balance`, so provenance is preserved.
        self.internal._subtract_balance(account, amount, max_notes);
    }

    /// @notice Increases the private balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[internal("private")]
    fn _increase_private_balance(to: AztecAddress, amount: u128) {
        let contract_address = self.context.this_address();
        // Safety: the label is an unconstrained choice of which sub-balance to credit (e.g. the
        // minter choosing the mint origin). It only selects a storage slot for the recipient's own
        // note, so an arbitrary value cannot affect any balance other than `to`'s.
        let label = unsafe { _read_label(contract_address, to, RECEIVE_LABEL_SLOT) };
        // Increases `amount` to the private balance of `to` under the chosen label, and emits a private balance note to `to`
        self.storage.private_balances.at(label).at(to).add(amount).deliver(
            MessageDelivery.ONCHAIN_CONSTRAINED,
        );
    }

    /// @notice Increases the public balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[internal("public")]
    fn _increase_public_balance(to: AztecAddress, amount: u128) {
        // Read the current public balance of `to`, add `amount` to it,
        let new_balance = self.storage.public_balances.at(to).read() + amount;
        // write the result back to the storage
        self.storage.public_balances.at(to).write(new_balance);
    }

    /// @notice Decreases the public balance of `from` by `amount`
    /// @param from The address of the account to decrease the balance of
    /// @param amount The amount of tokens to decrease the balance by
    #[internal("public")]
    fn _decrease_public_balance(from: AztecAddress, amount: u128) {
        // read the current public balance of `from`, subtract `amount`
        let new_balance = self.storage.public_balances.at(from).read() - amount;
        // update the public balance of `from` with the new balance
        self.storage.public_balances.at(from).write(new_balance);
    }

    /// @notice Completes a partial note
    /// @dev Completes a partial note and increases the balance of the commitment by `amount`
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param completer The address used to compute the validity commitment
    /// @param amount The amount of tokens to increase the balance of the commitment by
    #[internal("public")]
    fn _increase_commitment_balance(
        commitment: PartialUintNote,
        completer: AztecAddress,
        amount: u128,
    ) {
        commitment.complete(
            self.context,
            completer,
            self.storage.private_balances.at(NULL_LABEL).get_storage_slot(),
            amount,
        );
    }

    /// @notice Subtracts balance from the private balance of `account`, spending across labels
    /// @dev Pops the next label to spend from off the caller's queue, nullifies notes under that
    ///      label up to `max_notes`, and re-deposits any change into the same label. When the
    ///      popped label cannot cover the remaining amount, it recurses: the next frame pops the
    ///      next label, draining label A, then B, then C, ... This leverages the arbitrary-length
    ///      folding scheme, so the caller is not limited to a single label's balance.
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @param max_notes The maximum number of notes to process in a single call
    #[internal("private")]
    fn _subtract_balance(account: AztecAddress, amount: u128, max_notes: u32) {
        let contract_address = self.context.this_address();
        // Safety: the label is an unconstrained choice of which sub-balance to spend from. It only
        // selects a storage slot of the caller's own notes, so an arbitrary value cannot let the
        // caller spend funds they do not own.
        let label = unsafe { _pop_spend_label(contract_address, account) };

        let subtracted =
            self.storage.private_balances.at(label).at(account).try_sub(amount, max_notes);
        if subtracted >= amount {
            // We nullified notes adding up to at least `amount`, so we return the change to the
            // label it was spent from (preserving provenance of the remaining balance).
            self.storage.private_balances.at(label).at(account).add(subtracted - amount).deliver(
                MessageDelivery.ONCHAIN_CONSTRAINED,
            );
        } else {
            // Failing to subtract any amount under this label means there are no more notes to
            // nullify here and the caller did not queue a further label, so the balance is too low.
            assert(subtracted > 0, "Balance too low");

            // try_sub failed to nullify enough notes to reach the target amount, so we compute the
            // amount remaining and recurse, which pops the next label in the queue.
            let remaining = amount - subtracted;

            self.call_self.recurse_subtract_balance_internal(account, remaining);
        }
    }

    /// @notice Increases the total supply by `amount`
    /// @param amount The amount of tokens to increase the total supply by
    #[internal("public")]
    fn _increase_total_supply(amount: u128) {
        let new_supply = self.storage.total_supply.read() + amount;
        self.storage.total_supply.write(new_supply);
    }

    /// @notice Decreases the total supply by `amount`
    /// @param amount The amount to decrease the total supply by
    #[internal("public")]
    fn _decrease_total_supply(amount: u128) {
        let new_supply = self.storage.total_supply.read() - amount;
        self.storage.total_supply.write(new_supply);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @param to The address of the recipient
    /// @param completer The address used to compute the validity commitment
    /// @return The partial note that can be used to execute the transfer/mint
    #[internal("private")]
    fn _initialize_transfer_commitment(
        to: AztecAddress,
        completer: AztecAddress,
    ) -> PartialUintNote {
        let commitment = UintNote::partial(to, self.context, to, completer);

        commitment
    }

    /// @notice Mints tokens to a public balance and increases the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[internal("public")]
    fn _mint_to_public(to: AztecAddress, amount: u128) {
        self.internal._increase_public_balance(to, amount);
        self.internal._increase_total_supply(amount);

        self.emit(Transfer { from: AztecAddress::zero(), to, amount });
    }

    /// @notice Mints tokens to a private balance and enqueues a public call to increase the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[internal("private")]
    fn _mint_to_private(to: AztecAddress, amount: u128) {
        self.internal._increase_private_balance(to, amount);
        self.enqueue_self.increase_total_supply_internal(amount);
    }

    /// @notice Burns tokens from a public balance and decreases the total supply
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    #[internal("public")]
    fn _burn_public(from: AztecAddress, amount: u128) {
        self.internal._decrease_public_balance(from, amount);
        self.internal._decrease_total_supply(amount);

        self.emit(Transfer { from, to: AztecAddress::zero(), amount });
    }

    /// @notice Burns tokens from a private balance and enqueues a public call to decrease the total supply
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    #[internal("private")]
    fn _burn_private(from: AztecAddress, amount: u128) {
        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);
        self.enqueue_self.decrease_total_supply_internal(amount);
    }

}
