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
        oracle::random::random,
        protocol::{
            address::AztecAddress,
            hash::poseidon2_hash_with_separator,
            traits::{FromField, ToField},
        },
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

    /// @notice Emitted (privately, to the minter) when labeled value leaves the private domain --
    ///         either de-shielded to a public address or burned -- disclosing the origin label
    /// @dev Lets the issuer learn which origin label left private and how much. `kind` is
    ///      `SINK_DESHIELD` (to public address `to`) or `SINK_BURN` (`to` is the burner; value
    ///      destroyed). Once value is public it commingles, so flows in/out of a public address
    ///      cannot be told apart -- an accepted caveat of this model.
    #[event]
    struct LabelRetired {
        label: Field,
        to: AztecAddress,
        amount: u128,
        kind: u8,
    }

    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param private_balances The private balances of the token
    /// @param total_supply The total supply of the token
    /// @param public_balances The public balances of the token
    /// @param minter The account permissioned to mint the token
    /// @param label_counter Monotonic counter for allocating public origin labels H(counter)
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<Field, Owned<BalanceSet<Context>, Context>, Context>,
        total_supply: PublicMutable<u128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
        label_counter: PublicMutable<Field, Context>,
    }

    // Labeling is mandatory: there is no default/unlabeled bucket. Every private note lives under a
    // real origin label, a unique per-event id that traces all private flow from the tx that created
    // it. A label is created by whichever context creates the origin: H(seed) in private (random
    // seed, nullified), or H(counter) in public (a monotonic counter, since the AVM lacks randomness).

    // Domain separator for a private origin label H(seed). Uniqueness/non-replay is enforced by the
    // seed nullifier below. (Minting is minter-gated and the minter is immutable, so every private
    // mint label provably originates from the one minter without putting the minter in the hash.)
    // ASCII 'LABEL'
    global LABEL_SEPARATOR: Field = 0x4c4142454c;

    // Domain separator for the single-use nullifier pushed on a private origin seed, so the same seed
    // (hence label) can never be created twice -- a replay produces a duplicate nullifier and reverts.
    // ASCII 'SEED'
    global SEED_NULL_SEPARATOR: Field = 0x53454544;

    // Domain separator for a public origin label H(counter). Origins created in a PUBLIC context
    // (commitment completions) cannot use randomness, so they draw a monotonic public counter; the
    // separate separator keeps these disjoint from the private H(seed) labels.
    // ASCII 'COUNTER'
    global COUNTER_LABEL_SEPARATOR: Field = 0x434f554e544552;

    // Per-label sink applied by `_drain` to each drained (label, amount): credit the recipient, or
    // disclose the exit to the minter (de-shield or burn). DESHIELD/BURN double as the disclosure
    // `kind` so the minter can tell a de-shield (to a public address) from a burn (value destroyed).
    global SINK_CREDIT: u8 = 0;
    global SINK_DESHIELD: u8 = 1;
    global SINK_BURN: u8 = 2;

    // Capsule base slots used to pass the caller's chosen label(s) from the PXE into private
    // execution. These are PXE-local, scoped per address, and persist across the recursive
    // folding frames of `_drain` (unlike ephemeral arrays, which are frame-isolated). The values
    // are spaced far apart so the `CapsuleArray` element slots never collide.
    // Ordered FIFO queue of labels to spend from, scoped to the account being debited.
    global SPEND_LABELS_BASE_SLOT: Field = 0x10000000;
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
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, enqueues a public
    ///      call, and discloses each spent origin label to the minter (the value leaves the private
    ///      domain into the public address-label `to`).
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
        self.internal._drain(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES, SINK_DESHIELD, to);

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
        self.internal._drain(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES, SINK_DESHIELD, to);

        self.enqueue_self.increase_public_balance_internal(to, amount);

        // Only the sender will be able to complete the partial note
        let completer = self.msg_sender();
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        commitment.to_field()
    }

    /// @notice Transfer tokens from private balance to another private balance
    /// @dev Spends `from`'s notes across as many origin labels as needed, and for each label
    ///      drained credits `to` the same amount under the SAME label. The recipient therefore
    ///      inherits the exact origin(s) of the funds and cannot relabel them; a spend that draws
    ///      from N labels produces N labeled notes for `to` (provenance-preserving aggregation).
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
        // Drain `from`'s labels and credit `to` the same label(s): recipient inherits the origin(s).
        self.internal._drain(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES, SINK_CREDIT, to);
    }

    /// @notice Transfer tokens from a private balance to the recipient commitment, which must be already initialized.
    /// @dev Spends notes under a SINGLE origin label, emits a new note (UintNote) with any remaining
    ///      change, and completes the commitment into that same label so the recipient inherits the
    ///      funds' origin. A commitment is one note = one label and the completion only receives the
    ///      opaque commitment (no recipient address to deliver remainder notes to), so the funding
    ///      label must cover the full `amount`; multi-origin sends use multiple commitments.
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
        let contract_address = self.context.this_address();
        // Safety: the label is the caller's choice of which of `from`'s own sub-balances to fund
        // from; it only selects a storage slot of the caller's own notes. The commitment is then
        // completed into this SAME label, so the recipient's funds carry the spent label's origin
        // and cannot be relabeled.
        let label = unsafe { _pop_spend_label(contract_address, from) };
        self.internal._subtract_from_label(from, label, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        let completer = self.msg_sender();
        PartialUintNote::from_field(commitment).complete_from_private(
            self.context,
            completer,
            self.storage.private_balances.at(label).get_storage_slot(),
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

        // Re-entry creates a fresh private origin (per-event H(seed)). `from` is already on the
        // public record, so the label is a new per-tx id, not a function of `from`.
        self.internal._credit_fresh_origin(to, amount);
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

    /// @notice Recursively drains `from` across spend-queue labels, applying the sink per label
    /// @dev Continues a `_drain` under the next label in `from`'s queue when the current label
    ///      cannot cover the remaining amount. `mode` selects the per-label sink (credit `to` /
    ///      disclose a de-shield / disclose a burn); `to` is the recipient (CREDIT/DESHIELD) or the
    ///      burner (BURN).
    /// @param from The address being drained
    /// @param amount The amount of tokens left to drain
    /// @param mode The sink mode (SINK_CREDIT / SINK_DESHIELD / SINK_BURN)
    /// @param to The credit recipient, de-shield destination, or burner
    #[external("private")]
    #[only_self]
    fn recurse_drain_internal(from: AztecAddress, amount: u128, mode: u8, to: AztecAddress) {
        self.internal._drain(from, amount, RECURSIVE_TRANSFER_CALL_MAX_NOTES, mode, to);
    }

    /// @notice Recursively subtracts balance from a SINGLE label of `account`
    /// @dev Used to drain a funding label that exceeds the max notes limit when completing a
    ///      commitment. Unlike `recurse_drain_internal`, it stays on the same `label`
    ///      (it does not pop the next label), so the commitment funding remains single-origin.
    /// @param account The address of the account to subtract the balance from
    /// @param label The single origin label to drain
    /// @param amount The amount of tokens left to subtract
    #[external("private")]
    #[only_self]
    fn recurse_subtract_from_label_internal(account: AztecAddress, label: Field, amount: u128) {
        self.internal._subtract_from_label(
            account,
            label,
            amount,
            RECURSIVE_TRANSFER_CALL_MAX_NOTES,
        );
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
        // Public-funded origin: allocate a fresh public label H(counter). The completer cannot
        // choose it (it's the contract's counter), so this cannot stamp an arbitrary origin.
        let label = self.internal._next_public_label();
        self.internal._increase_commitment_balance(
            PartialUintNote::from_field(commitment),
            completer,
            label,
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
    /// @dev The label to query is read from a capsule (which must be set -- there is no default
    ///      bucket), so the caller can inspect any individual label balance without changing this
    ///      method's signature.
    /// @param owner The address to query
    /// @return The private balance of the address under the chosen label
    #[external("utility")]
    unconstrained fn balance_of_private(owner: AztecAddress) -> u128 {
        let contract_address = self.context.this_address();
        // The queried label is the caller's free choice of which sub-balance to read; it must be
        // set (no default bucket) and only selects a storage slot, so it leaks/affects nothing else.
        let label: Option<Field> =
            aztec::oracle::capsules::load(contract_address, QUERY_LABEL_SLOT, owner);
        assert(label.is_some(), "no query label");
        self.storage.private_balances.at(label.unwrap()).at(owner).balance_of()
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
        // Minted to a commitment in public context (no AVM randomness for an H(seed)), so allocate
        // a fresh public origin label H(counter) -- unique per event, completer cannot choose it.
        let label = self.internal._next_public_label();
        self.internal._increase_commitment_balance(
            PartialUintNote::from_field(commitment),
            completer,
            label,
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

    /// @notice Derives the mint origin label `H(seed)`
    /// @dev Minting is minter-gated and the minter is immutable, so every label produced here
    ///      provably comes from the one minter; the seed only needs to be unique, which the mint's
    ///      single-use seed nullifier enforces. Deterministic: anyone can recompute `H(seed)`.
    /// @param seed The mint seed (unique per mint; nullified at mint time)
    /// @return The origin label
    #[contract_library_method]
    fn _label(seed: Field) -> Field {
        poseidon2_hash_with_separator([seed], LABEL_SEPARATOR)
    }

    /// @notice Allocates the next public origin label `H(counter)` and advances the counter
    /// @dev For origins created in a PUBLIC context (commitment completions), where the AVM has no
    ///      randomness. The monotonic counter makes each label unique without a nullifier, and the
    ///      counter is contract state (not a caller input), so a completer cannot choose the label.
    /// @return A fresh public origin label
    #[internal("public")]
    fn _next_public_label() -> Field {
        let counter = self.storage.label_counter.read() + 1;
        self.storage.label_counter.write(counter);
        poseidon2_hash_with_separator([counter], COUNTER_LABEL_SEPARATOR)
    }

    /// @notice Pops the next label to spend from for `account` off the caller-provided queue
    /// @dev Unconstrained: the label is the caller's free choice of which sub-balance to spend
    ///      from, and only selects a storage slot of the caller's own notes. Backed by a capsule
    ///      array so it persists across the recursive `_drain` frames. Reverts when the
    ///      queue is empty (no default bucket exists).
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
        // Mandatory labeling: there is no default bucket to fall back to, so the caller must name
        // which origin label(s) to spend from.
        assert(queue.len() != 0, "no spend label");
        let label = queue.get(0);
        queue.remove(0);
        label
    }

    /// @notice Credits `to` under a brand-new private origin label `H(seed)` and nullifies the seed
    /// @dev The single place that mints a NEW private origin: used by both `mint_to_private` and
    ///      `public->private` re-entry. The seed only needs to be unique (it is not a meaningful
    ///      minter choice); it is drawn from fresh `random()`. Single-use: the seed nullifier makes
    ///      a second use of the same seed (hence label) unprovable, so
    ///      every origin is a unique per-event id.
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to credit
    #[internal("private")]
    fn _credit_fresh_origin(to: AztecAddress, amount: u128) {
        // Safety: the seed only selects the (new) origin bucket of the recipient's own notes; a
        // (vanishingly unlikely, or maliciously replayed) repeat reverts on the duplicate nullifier.
        let seed = unsafe { random() };
        let label = _label(seed);

        // Nullify the seed so this origin label can never be created again.
        self.context.push_nullifier(poseidon2_hash_with_separator([seed], SEED_NULL_SEPARATOR));

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

    /// @notice Completes a partial note into the given origin label's slot
    /// @dev Completes a partial note and increases the balance of the commitment by `amount`,
    ///      bucketed under `label` (the funding origin), so commitment value carries provenance.
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param completer The address used to compute the validity commitment
    /// @param label The origin label the completed note is credited under
    /// @param amount The amount of tokens to increase the balance of the commitment by
    #[internal("public")]
    fn _increase_commitment_balance(
        commitment: PartialUintNote,
        completer: AztecAddress,
        label: Field,
        amount: u128,
    ) {
        commitment.complete(
            self.context,
            completer,
            self.storage.private_balances.at(label).get_storage_slot(),
            amount,
        );
    }

    /// @notice Drains `amount` from `from` across spend-queue labels, applying `mode`'s sink per label
    /// @dev The one canonical multi-label drain. Pops the next label off `from`'s spend queue,
    ///      nullifies notes under it up to `max_notes`, returns any change to the SAME label
    ///      (preserving provenance), applies the per-label sink, and recurses to the next queued
    ///      label when one cannot cover the remainder. Replaces the former private->private /
    ///      de-shield / burn drains, which differed only in this per-label sink.
    /// @param from The address being drained
    /// @param amount The amount of tokens to drain
    /// @param max_notes The maximum number of notes to process in a single call
    /// @param mode The per-label sink (SINK_CREDIT / SINK_DESHIELD / SINK_BURN)
    /// @param to The credit recipient (CREDIT), de-shield destination (DESHIELD), or burner (BURN)
    #[internal("private")]
    fn _drain(from: AztecAddress, amount: u128, max_notes: u32, mode: u8, to: AztecAddress) {
        let contract_address = self.context.this_address();
        // Safety: the label only selects a storage slot of `from`'s own notes; an arbitrary value
        // cannot spend funds they do not own (try_sub finds nothing and the assert below reverts).
        let label = unsafe { _pop_spend_label(contract_address, from) };

        let subtracted =
            self.storage.private_balances.at(label).at(from).try_sub(amount, max_notes);
        if subtracted >= amount {
            // Return the change to `from` under the source label (preserving provenance), ...
            self.storage.private_balances.at(label).at(from).add(subtracted - amount).deliver(
                MessageDelivery.ONCHAIN_CONSTRAINED,
            );
            // ... and apply the sink for the full drained amount under this label.
            self.internal._apply_sink(mode, label, to, amount);
        } else {
            // This label is exhausted within `max_notes`; apply the sink for what it gave, then
            // recurse to the next queued label for the remainder.
            assert(subtracted > 0, "Balance too low");

            self.internal._apply_sink(mode, label, to, subtracted);
            let remaining = amount - subtracted;

            self.call_self.recurse_drain_internal(from, remaining, mode, to);
        }
    }

    /// @notice Applies a drain's per-label sink: credit the recipient, or disclose the exit to the minter
    /// @dev SINK_CREDIT credits `to` under `label`, so a private->private recipient inherits the exact
    ///      source label and cannot relabel. SINK_DESHIELD / SINK_BURN emit a `LabelRetired` event
    ///      (kind = the mode) privately to the minter, so the issuer learns which origin left the
    ///      private domain and how much (de-shield to a public address, or burn).
    /// @param mode The sink mode
    /// @param label The origin label being credited or retired
    /// @param to The credit recipient (CREDIT), de-shield destination (DESHIELD), or burner (BURN)
    /// @param amount The amount for this label
    #[internal("private")]
    fn _apply_sink(mode: u8, label: Field, to: AztecAddress, amount: u128) {
        if mode == SINK_CREDIT {
            self.storage.private_balances.at(label).at(to).add(amount).deliver(
                MessageDelivery.ONCHAIN_CONSTRAINED,
            );
        } else {
            // SINK_DESHIELD or SINK_BURN: disclose the exit to the minter; `kind` = `mode`.
            let minter = self.storage.minter.read();
            self.emit(LabelRetired { label, to, amount, kind: mode }).deliver_to(
                minter,
                MessageDelivery.ONCHAIN_CONSTRAINED,
            );
        }
    }

    /// @notice Subtracts `amount` from a SINGLE origin label of `account`, returning change to it
    /// @dev Like `_drain` but stays on a fixed `label` instead of popping the spend
    ///      queue: it recurses over note batches of the SAME label until `amount` is covered. Used
    ///      to fund a commitment from one origin (commitments hold a single label). Reverts if the
    ///      label cannot cover `amount`.
    /// @param account The address of the account to subtract the balance from
    /// @param label The single origin label to drain
    /// @param amount The amount of tokens to subtract
    /// @param max_notes The maximum number of notes to process in a single call
    #[internal("private")]
    fn _subtract_from_label(account: AztecAddress, label: Field, amount: u128, max_notes: u32) {
        let subtracted =
            self.storage.private_balances.at(label).at(account).try_sub(amount, max_notes);
        if subtracted >= amount {
            // Return the change to `account` under the same label (preserving provenance).
            self.storage.private_balances.at(label).at(account).add(subtracted - amount).deliver(
                MessageDelivery.ONCHAIN_CONSTRAINED,
            );
        } else {
            // No more notes to nullify under this label; the single-label balance is too low.
            assert(subtracted > 0, "Balance too low");

            // Recurse on the SAME label (not the next in the queue) to drain its remaining notes.
            let remaining = amount - subtracted;

            self.call_self.recurse_subtract_from_label_internal(account, label, remaining);
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

    /// @notice Mints tokens to a private balance under a fresh, unique origin label
    /// @dev Derives label = H(seed) from a per-mint random seed and pushes a single-use nullifier
    ///      on the seed, so the same label can never be minted again (a replayed seed reverts on
    ///      the duplicate nullifier). Minting is minter-gated by the caller, so every label here
    ///      originates from the one minter.
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[internal("private")]
    fn _mint_to_private(to: AztecAddress, amount: u128) {
        // A mint creates a fresh private origin (H(seed) + single-use nullifier) and bumps supply.
        self.internal._credit_fresh_origin(to, amount);
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
        // Drain `from`'s labels and disclose each burned origin to the minter (kind = BURN), so the
        // issuer learns which origins left the private domain -- symmetric with a de-shield.
        self.internal._drain(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES, SINK_BURN, from);
        self.enqueue_self.decrease_total_supply_internal(amount);
    }

}
