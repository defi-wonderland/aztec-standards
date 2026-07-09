pub mod types;
pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract MultiToken {
    // aztec library
    use aztec::{
        macros::{
            events::event,
            functions::{authorize_once, external, initializer, internal, only_self, view},
            storage::storage,
        },
        protocol::{address::AztecAddress, traits::{FromField, ToField}},
        state_vars::{Map, Owned, PublicImmutable, PublicMutable, StateVariable},
    };
    // compression library
    use compressed_string::FieldCompressedString;
    // authorization hook contract (id-bearing ARC-403 interface)
    use multitoken_authorization_contract::MultiTokenAuthorizationContract;
    // multitoken note structs + per-id balance set (owner-scoped wrapper over PrivateSet<MultiTokenNote>)
    use crate::types::{
        balance::MultiBalanceSet,
        multitoken_note::{MultiTokenNote, PartialMultiTokenNote},
    };

    // gas-optimized max notes for initial transfer call
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    // max notes transfer for recursive transfer call if initial max notes are exceeded
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    // Sentinel address used in TransferSingle events to represent the private side of a balance change.
    // sha224sum 'PRIVATE_ADDRESS'
    global PRIVATE_ADDRESS_MAGIC_VALUE: AztecAddress =
        AztecAddress::from_field(0x1ea7e01501975545617c2e694d931cb576b691a4a867fed81ebd3264);

    /// @notice Emitted only on operations whose token id is already revealed on-chain (any public-balance write or
    /// public commitment completion). Fully-private operations (transfer_private_to_private,
    /// transfer_private_to_commitment, mint_to_private, burn_private) emit no event, as an id-bearing event would leak
    /// the token id.
    #[event]
    struct TransferSingle {
        from: AztecAddress,
        to: AztecAddress,
        id: Field,
        amount: u128,
    }

    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param private_balances A single private set of MultiTokenNotes; each note self-describes its token id
    /// @param public_balances The public balances, keyed by token id then owner
    /// @param minter The account permissioned to mint any token id
    /// @param auth_contract The optional ARC-403 authorization contract (zero address to disable)
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        // PRIVATE: a single note set; `Owned` threads the owner into each note and keeps ONE base slot. Each note
        // self-describes its token id; per-owner scoping is `private_balances.at(owner)`, which yields a
        // `MultiBalanceSet` whose ops are scoped to a token id via `select(token_id == id)`.
        private_balances: Owned<MultiBalanceSet<Context>, Context>,
        // PUBLIC: id -> owner -> balance. Keyed by id by necessity (public == id is visible).
        public_balances: Map<Field, Map<AztecAddress, PublicMutable<u128, Context>, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
        auth_contract: PublicImmutable<AztecAddress, Context>,
    }

    /// @notice Initializes the multi-token with a minter
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param minter The address of the minter
    /// @param auth_contract The address of the authorization contract (zero address to disable)
    #[external("public")]
    #[initializer]
    fn constructor_with_minter(
        name: FieldCompressedString,
        symbol: FieldCompressedString,
        minter: AztecAddress,
        auth_contract: AztecAddress,
    ) {
        self.storage.name.initialize(name);
        self.storage.symbol.initialize(symbol);
        self.storage.minter.initialize(minter);
        self.storage.auth_contract.initialize(auth_contract);
    }

    /** ==========================================================
    * ========================= PRIVATE =========================
    * ======================================================== */

    /// @notice Transfer tokens from a private balance to another private balance
    /// @dev Spends notes, emits a new note with any remaining change, and sends a note to the recipient.
    ///      Fully private: no event and no public effect, so the token id and amount stay hidden.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param id The token id to transfer
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        id: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._call_auth_private(from, id, amount);

        self.internal._decrease_private_balance(from, id, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        self.internal._increase_private_balance(to, id, amount);
    }

    /// @notice Transfer tokens from a private balance to a public balance
    /// @dev Spends notes, emits a new note with any remaining change, and enqueues a public call to credit `to`.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param id The token id to transfer
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        id: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._call_auth_private(from, id, amount);

        self.internal._decrease_private_balance(from, id, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        self.enqueue_self.increase_public_balance_internal(to, id, amount);
    }

    /// @notice Transfer tokens from a private balance to the recipient commitment, which must already be initialized
    /// @dev Spends notes, emits a new note with any remaining change, and completes the commitment with `(id, amount)`.
    ///      The `from` payer must be the completer of the partial note.
    /// @param from The address of the sender
    /// @param id The token id to transfer
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        id: Field,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._call_auth_private(from, id, amount);

        self.internal._decrease_private_balance(from, id, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        let completer = self.msg_sender();
        PartialMultiTokenNote::from_field(commitment).complete_from_private(
            self.context,
            completer,
            self.storage.private_balances.get_storage_slot(),
            id,
            amount,
        );
    }

    /// @notice Transfer tokens from a public balance to a private balance
    /// @dev Enqueues a public call to decrease `from`'s balance and emits a private note to `to`.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param id The token id to transfer
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        id: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._call_auth_private(from, id, amount);

        self.enqueue_self.decrease_public_balance_internal(from, id, amount);

        self.internal._increase_private_balance(to, id, amount);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @dev id-agnostic: the completer binds the token id and amount at completion. Spends nothing, so no authwit.
    /// @param to The address of the recipient
    /// @param completer The address allowed to complete the partial note
    /// @return commitment The partial note initialized for the transfer/mint commitment (privacy entrance)
    #[external("private")]
    fn initialize_transfer_commitment(to: AztecAddress, completer: AztecAddress) -> Field {
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        commitment.to_field()
    }

    /// @notice Recursively subtracts balance of `id` from a private balance
    /// @dev Used to subtract private balances that exceed the max notes limit in a single frame
    /// @param account The address of the account to subtract the balance from
    /// @param id The token id to subtract
    /// @param amount The amount of tokens to subtract
    /// @return The change to return to the owner
    #[external("private")]
    #[only_self]
    fn recurse_subtract_balance_internal(account: AztecAddress, id: Field, amount: u128) -> u128 {
        self.internal._subtract_balance(account, id, amount, RECURSIVE_TRANSFER_CALL_MAX_NOTES)
    }

    /** ==========================================================
    * ========================= PUBLIC ==========================
    * ======================================================== */

    /// @notice Transfers tokens from a public balance to another public balance
    /// @dev Public call to decrease `from`'s balance and increase `to`'s balance; emits a TransferSingle event.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param id The token id to transfer
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn transfer_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        id: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._call_auth_public(from, id, amount);

        self.internal._decrease_public_balance(from, id, amount);
        self.internal._increase_public_balance(to, id, amount);

        self.emit(TransferSingle { from, to, id, amount });
    }

    /// @notice Finalizes a transfer of `amount` of `id` from public balance of `from` to a commitment
    /// @dev The transfer must be prepared by calling `initialize_transfer_commitment` first. The `from` payer
    ///      (msg_sender) must be the completer of the partial note.
    /// @param from The address of the sender
    /// @param id The token id to transfer
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn transfer_public_to_commitment(
        from: AztecAddress,
        id: Field,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._call_auth_public(from, id, amount);

        self.internal._decrease_public_balance(from, id, amount);

        let completer = self.msg_sender();
        self.internal._complete_commitment(
            PartialMultiTokenNote::from_field(commitment),
            completer,
            id,
            amount,
        );

        self.emit(TransferSingle { from, to: PRIVATE_ADDRESS_MAGIC_VALUE, id, amount });
    }

    /// @notice Increases the public balance of `owner` for `id` by `amount`
    /// @param owner The address of the recipient
    /// @param id The token id to increase the balance of
    /// @param amount The amount of tokens to increase the balance by
    #[external("public")]
    #[only_self]
    fn increase_public_balance_internal(owner: AztecAddress, id: Field, amount: u128) {
        self.internal._increase_public_balance(owner, id, amount);

        self.emit(TransferSingle { from: PRIVATE_ADDRESS_MAGIC_VALUE, to: owner, id, amount });
    }

    /// @notice Decreases the public balance of `owner` for `id` by `amount`
    /// @param owner The address of the sender
    /// @param id The token id to decrease the balance of
    /// @param amount The amount of tokens to decrease the balance by
    #[external("public")]
    #[only_self]
    fn decrease_public_balance_internal(owner: AztecAddress, id: Field, amount: u128) {
        self.internal._decrease_public_balance(owner, id, amount);

        self.emit(TransferSingle { from: owner, to: PRIVATE_ADDRESS_MAGIC_VALUE, id, amount });
    }

    /** ==========================================================
    * ====================== VIEW FUNCTIONS =====================
    * ======================================================== */

    /// @notice Returns the public balance of `owner` for `id`
    /// @param owner The address of the owner
    /// @param id The token id to query
    /// @return The public balance of `owner` for `id`
    #[external("public")]
    #[view]
    fn balance_of_public(owner: AztecAddress, id: Field) -> u128 {
        self.storage.public_balances.at(id).at(owner).read()
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

    /// @notice Returns the minter of the token
    /// @return The minter address
    #[external("public")]
    #[view]
    fn get_minter() -> AztecAddress {
        self.storage.minter.read()
    }

    /// @notice Returns the ARC-403 authorization hook contract address
    /// @return The auth contract address (zero address means authorization is disabled)
    #[external("public")]
    #[view]
    fn get_auth_contract() -> AztecAddress {
        self.storage.auth_contract.read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    /// @notice Returns the private balance of `owner` for `id`
    /// @dev Off-chain utility that pages through the owner's notes, filtered by token id, and sums their values. Its
    ///      cost grows with the owner's note count; there is no on-chain or proving cost, and no fixed cap.
    /// @param owner The address to query
    /// @param id The token id to query
    /// @return The private balance of `owner` for `id`
    #[external("utility")]
    unconstrained fn balance_of_private(owner: AztecAddress, id: Field) -> u128 {
        self.storage.private_balances.at(owner).balance_of(id)
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    /// @notice Mints `amount` of `id` to a private balance
    /// @dev Asserts that the caller is the minter; fully private, so no event and no public effect.
    /// @param to The address of the recipient
    /// @param id The token id to mint
    /// @param amount The amount of tokens to mint
    #[external("private")]
    fn mint_to_private(to: AztecAddress, id: Field, amount: u128) {
        _validate_minter(self.msg_sender(), self.storage.minter.read());

        self.internal._increase_private_balance(to, id, amount);
    }

    /// @notice Mints `amount` of `id` to a public balance
    /// @dev Asserts that the caller is the minter
    /// @param to The address of the recipient
    /// @param id The token id to mint
    /// @param amount The amount of tokens to mint
    #[external("public")]
    fn mint_to_public(to: AztecAddress, id: Field, amount: u128) {
        _validate_minter(self.msg_sender(), self.storage.minter.read());

        self.internal._increase_public_balance(to, id, amount);

        self.emit(TransferSingle { from: AztecAddress::zero(), to, id, amount });
    }

    /// @notice Finalizes a mint of `amount` of `id` to a commitment
    /// @dev Asserts that the caller is the minter; the minter (msg_sender) is the completer
    /// @param id The token id to mint
    /// @param commitment The partial note representing the mint commitment (privacy entrance)
    /// @param amount The amount of tokens to mint
    #[external("public")]
    fn mint_to_commitment(id: Field, commitment: Field, amount: u128) {
        let completer = self.msg_sender();
        _validate_minter(completer, self.storage.minter.read());

        self.internal._complete_commitment(
            PartialMultiTokenNote::from_field(commitment),
            completer,
            id,
            amount,
        );

        self.emit(
            TransferSingle {
                from: AztecAddress::zero(),
                to: PRIVATE_ADDRESS_MAGIC_VALUE,
                id,
                amount,
            },
        );
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns `amount` of `id` from a private balance
    /// @dev Spends notes and emits any remaining change; fully private, so no event and no public effect.
    /// @param from The address of the sender
    /// @param id The token id to burn
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn burn_private(from: AztecAddress, id: Field, amount: u128, _nonce: Field) {
        self.internal._call_auth_private(from, id, amount);

        self.internal._decrease_private_balance(from, id, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);
    }

    /// @notice Burns `amount` of `id` from a public balance
    /// @dev Decreases the public balance of `from` and emits a TransferSingle event with `to = zero`.
    /// @param from The address of the sender
    /// @param id The token id to burn
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn burn_public(from: AztecAddress, id: Field, amount: u128, _nonce: Field) {
        self.internal._call_auth_public(from, id, amount);

        self.internal._decrease_public_balance(from, id, amount);

        self.emit(TransferSingle { from, to: AztecAddress::zero(), id, amount });
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// @notice ARC-403: calls the public authorization hook when one is configured
    /// @dev Invoked from external public functions; no-ops when auth_contract is zero
    /// @param from The address tokens are moved from
    /// @param id The token id being moved (stays private when called from private origin)
    /// @param amount The amount of tokens being moved
    #[internal("public")]
    fn _call_auth_public(from: AztecAddress, id: Field, amount: u128) {
        let auth = self.storage.auth_contract.read();
        if !auth.eq(AztecAddress::zero()) {
            let selector = self.context.selector().to_field();
            self.call(MultiTokenAuthorizationContract::at(auth).authorize_public(
                from,
                id,
                amount,
                selector,
            ));
        }
    }

    /// @notice ARC-403: calls the private authorization hook when one is configured
    /// @dev Invoked from external private functions; no-ops when auth_contract is zero. The id stays in the private
    ///      domain (a hook that derives public effects from it is the hook author's responsibility).
    /// @param from The address tokens are moved from
    /// @param id The token id being moved
    /// @param amount The amount of tokens being moved
    #[internal("private")]
    fn _call_auth_private(from: AztecAddress, id: Field, amount: u128) {
        let auth = self.storage.auth_contract.read();
        if !auth.eq(AztecAddress::zero()) {
            let selector = self.context.selector().to_field();
            self.call(MultiTokenAuthorizationContract::at(auth).authorize_private(
                from,
                id,
                amount,
                selector,
            ));
        }
    }

    /// @notice Validates that the caller is the minter
    /// @param sender The address of the caller
    /// @param minter The address of the authorized minter
    #[contract_library_method]
    fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }

    /// @notice Decreases the private balance of `account` for `id` by `amount` and re-credits any change
    /// @param account The address of the account to decrease the balance of
    /// @param id The token id to decrease the balance of
    /// @param amount The amount of tokens to decrease the balance by
    /// @param max_notes The maximum number of notes to process in a single call
    #[internal("private")]
    fn _decrease_private_balance(account: AztecAddress, id: Field, amount: u128, max_notes: u32) {
        // Subtract `amount` of `id`, then re-credit any change as a same-id note.
        let change = self.internal._subtract_balance(account, id, amount, max_notes);
        self.internal._increase_private_balance(account, id, change);
    }

    /// @notice Increases the private balance of `to` for `id` by `amount`
    /// @param to The address of the recipient
    /// @param id The token id to increase the balance of
    /// @param amount The amount of tokens to increase the balance by
    #[internal("private")]
    fn _increase_private_balance(to: AztecAddress, id: Field, amount: u128) {
        self.storage.private_balances.at(to).add(id, amount);
    }

    /// @notice Subtracts `amount` of `id` from a private balance, recursing across frames if necessary
    /// @dev Mirrors the balance_set algorithm (min-sum preprocessor + value-DESC sort + max_notes cap + cross-frame
    ///      recursion) over MultiTokenNote, plus a constrained `select(token_id == id)` for per-id isolation.
    /// @param account The address of the account to subtract the balance from
    /// @param id The token id to subtract
    /// @param amount The amount of tokens to subtract
    /// @param max_notes The maximum number of notes to process in a single call
    /// @return The change to return to the owner
    #[internal("private")]
    fn _subtract_balance(account: AztecAddress, id: Field, amount: u128, max_notes: u32) -> u128 {
        let subtracted = self.storage.private_balances.at(account).try_sub(id, amount, max_notes);
        if subtracted >= amount {
            // We have achieved our goal of nullifying notes that add up to more than amount, so we return the change.
            subtracted - amount
        } else {
            // Failing to subtract any amount means that the owner was unable to produce more notes of this id that
            // could be nullified.
            assert(subtracted > 0, "Balance too low");

            // We covered part of `amount`; fetch the remainder in a fresh frame (fresh note budget).
            let remaining = amount - subtracted;

            self.call_self.recurse_subtract_balance_internal(account, id, remaining)
        }
    }

    /// @notice Increases the public balance of `owner` for `id` by `amount`
    /// @param owner The address of the recipient
    /// @param id The token id to increase the balance of
    /// @param amount The amount of tokens to increase the balance by
    #[internal("public")]
    fn _increase_public_balance(owner: AztecAddress, id: Field, amount: u128) {
        let new_balance = self.storage.public_balances.at(id).at(owner).read() + amount;
        self.storage.public_balances.at(id).at(owner).write(new_balance);
    }

    /// @notice Decreases the public balance of `owner` for `id` by `amount`
    /// @param owner The address of the account to decrease the balance of
    /// @param id The token id to decrease the balance of
    /// @param amount The amount of tokens to decrease the balance by
    #[internal("public")]
    fn _decrease_public_balance(owner: AztecAddress, id: Field, amount: u128) {
        let new_balance = self.storage.public_balances.at(id).at(owner).read() - amount;
        self.storage.public_balances.at(id).at(owner).write(new_balance);
    }

    /// @notice Completes a partial note, crediting `amount` of `id` to the commitment
    /// @dev `complete` reverts unless `completer` reproduces the validity commitment pushed at creation. The
    ///      `base_slot` is the SINGLE slot of `private_balances` (not per-owner, not per-id) - the owner is bound
    ///      inside the commitment H(owner, randomness).
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param completer The address used to compute the validity commitment
    /// @param id The token id to credit
    /// @param amount The amount of tokens to credit
    #[internal("public")]
    fn _complete_commitment(
        commitment: PartialMultiTokenNote,
        completer: AztecAddress,
        id: Field,
        amount: u128,
    ) {
        commitment.complete(
            self.context,
            completer,
            self.storage.private_balances.get_storage_slot(),
            id,
            amount,
        );
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @param to The address of the recipient
    /// @param completer The address used to compute the validity commitment
    /// @return The partial note that can be used to execute the transfer/mint
    #[internal("private")]
    fn _initialize_transfer_commitment(
        to: AztecAddress,
        completer: AztecAddress,
    ) -> PartialMultiTokenNote {
        MultiTokenNote::partial(to, self.context, to, completer)
    }

}
