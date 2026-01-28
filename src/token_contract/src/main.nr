pub mod test;
pub mod types;

use aztec::macros::aztec;

#[aztec]
pub contract Token {
    // aztec library
    use aztec::{
        authwit::auth::{
            assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
        },
        context::PrivateContext,
        macros::{functions::{external, initializer, internal, only_self, view}, storage::storage},
        messages::message_delivery::MessageDelivery,
        protocol_types::{
            address::AztecAddress,
            constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            contract_class_id::ContractClassId,
            traits::{FromField, ToField},
        },
        state_vars::{
            Map, Owned, public_immutable::PublicImmutable, public_mutable::PublicMutable,
            StateVariable,
        },
    };
    // note library
    use uint_note::uint_note::{PartialUintNote, UintNote};
    // compression library
    use compressed_string::FieldCompressedString;
    // contract instance registry
    use contract_instance_registry::ContractInstanceRegistry;
    // private balance library
    use crate::types::balance_set::BalanceSet;

    // gas-optimized max notes for initial transfer call
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    // max notes transfer for recursive transfer call if initial max notes are exceeded
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    // Rounding direction that the vault uses to calculate shares and assets
    global ROUND_DOWN: bool = false;
    global ROUND_UP: bool = true;

    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param private_balances The private balances of the token
    /// @param total_supply The total supply of the token
    /// @param public_balances The public balances of the token
    /// @param minter The account permissioned to mint the token
    /// @param upgrade_authority The address with permission to upgrade the contract
    /// @param asset The underlying asset for yield-bearing vault functionality
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Owned<BalanceSet<Context>, Context>,
        total_supply: PublicMutable<u128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
        upgrade_authority: PublicImmutable<AztecAddress, Context>,
        asset: PublicImmutable<AztecAddress, Context>,
    }

    /// @notice Initializes the token with an asset
    /// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param asset The underlying asset for the yield bearing token
    #[external("public")]
    #[initializer]
    fn constructor_with_asset(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        asset: AztecAddress,
        upgrade_authority: AztecAddress,
    ) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.decimals.initialize(decimals);
        self.storage.asset.initialize(asset);

        self.storage.upgrade_authority.initialize(upgrade_authority);
    }

    /// @notice Initializes the token with an initial supply
    /// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param initial_supply The initial supply of the token
    /// @param to The address to mint the initial supply to
    /// @param upgrade_authority The address of the upgrade authority (zero address if not upgradeable)
    #[external("public")]
    #[initializer]
    fn constructor_with_initial_supply(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        initial_supply: u128,
        to: AztecAddress,
        upgrade_authority: AztecAddress,
    ) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.decimals.initialize(decimals);

        self.internal._mint_to_public(to, initial_supply);

        self.storage.upgrade_authority.initialize(upgrade_authority);
    }

    /// @notice Initializes the token with a minter
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param minter The address of the minter
    /// @param upgrade_authority The address of the upgrade authority (zero address if not upgradeable)
    #[external("public")]
    #[initializer]
    fn constructor_with_minter(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        minter: AztecAddress,
        upgrade_authority: AztecAddress,
    ) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.decimals.initialize(decimals);

        self.storage.minter.initialize(minter);
        self.storage.upgrade_authority.initialize(upgrade_authority);
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
    #[external("private")]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

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
    #[external("private")]
    fn transfer_private_to_public_with_commitment(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) -> Field {
        _validate_from_private::<4>(self.context, from);

        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        self.enqueue_self.increase_public_balance_internal(to, amount);

        // Only the sender will be able to complete the partial note
        let completer = self.msg_sender().unwrap();
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        commitment.to_field()
    }

    /// @notice Transfer tokens from private balance to another private balance
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and sends a note to the recipient
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        self.internal._increase_private_balance(to, amount);
    }

    /// @notice Transfer tokens from private balance to the recipient's commitment (recipient must create a commitment first)
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
    ///      `from` will also be the completer of the partial note
    /// @param from The address of the sender
    /// @param commitment The partial note representing the commitment (privacy entrance that the recipient shares with the sender)
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        let completer = self.msg_sender().unwrap();
        PartialUintNote::from_field(commitment).complete_from_private(
            self.context,
            completer,
            amount,
        );
    }

    /// @notice Transfer tokens from public balance to private balance
    /// @dev Enqueues a public call to decrease account balance and emits a new note with balance difference
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

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
    /// @dev Used to subtract private balances that exceed the max notes limit
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @return The change to return to the owner
    #[external("private")]
    #[only_self]
    fn recurse_subtract_balance_internal(account: AztecAddress, amount: u128) -> u128 {
        self.internal._subtract_balance(account, amount, RECURSIVE_TRANSFER_CALL_MAX_NOTES)
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
    #[external("public")]
    fn transfer_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._validate_from_public(from);

        self.internal._decrease_public_balance(from, amount);
        self.internal._increase_public_balance(to, amount);
    }

    /// @notice Finalizes a transfer of token `amount` from public balance of `from` to a commitment of `to`
    /// @dev The transfer must be prepared by calling `initialize_transfer_commitment` first and the resulting
    /// `commitment` must be passed as an argument to this function.
    /// @dev The sender will be used as the completer for the partial note.
    /// @param from The address of the sender
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn transfer_public_to_commitment(
        from: AztecAddress,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._validate_from_public(from);

        self.internal._decrease_public_balance(from, amount);

        let completer = self.msg_sender().unwrap();
        self.internal._increase_commitment_balance(
            PartialUintNote::from_field(commitment),
            completer,
            amount,
        );
    }

    /// @notice Increases the public balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[external("public")]
    #[only_self]
    fn increase_public_balance_internal(to: AztecAddress, amount: u128) {
        self.internal._increase_public_balance(to, amount);
    }

    /// @notice Decreases the public balance of `from` by `amount`
    /// @param from The address of the sender
    /// @param amount The amount of tokens to decrease the balance by
    #[external("public")]
    #[only_self]
    fn decrease_public_balance_internal(from: AztecAddress, amount: u128) {
        self.internal._decrease_public_balance(from, amount);
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

    /// @notice Returns the private balance of an account
    /// @param owner The address to query
    /// @return The private balance of the address
    #[external("utility")]
    unconstrained fn balance_of_private(owner: AztecAddress) -> u128 {
        self.storage.private_balances.at(owner).balance_of()
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
        _validate_minter(self.msg_sender().unwrap(), self.storage.minter.read());

        self.internal._mint_to_private(to, amount);
    }

    /// @notice Mints tokens to an address publicly
    /// @dev Increases the public balance of `to` by `amount` and the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[external("public")]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        _validate_minter(self.msg_sender().unwrap(), self.storage.minter.read());

        self.internal._mint_to_public(to, amount);
    }

    /// @notice Finalizes a mint to a commitment
    /// @dev Finalizes a mint to a commitment and updates the total supply
    /// @param commitment The partial note representing the mint commitment (privacy entrance)
    /// @param amount The amount of tokens to mint
    #[external("public")]
    fn mint_to_commitment(commitment: Field, amount: u128) {
        let sender = self.msg_sender().unwrap();
        _validate_minter(sender, self.storage.minter.read());
        let completer = sender;
        self.internal._increase_total_supply(amount);
        self.internal._increase_commitment_balance(
            PartialUintNote::from_field(commitment),
            completer,
            amount,
        );
    }

    /// @notice Internal function to increase the total supply by `amount`
    /// @param amount The amount to increase the total supply by
    #[external("public")]
    #[only_self]
    fn increase_total_supply_internal(amount: u128) {
        self.internal._increase_total_supply(amount);
    }

    /// @notice Internal function to mint tokens to a public balance
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[external("public")]
    #[only_self]
    fn mint_to_public_internal(to: AztecAddress, amount: u128) {
        self.internal._mint_to_public(to, amount);
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns tokens from a private balance
    /// @dev Burns tokens from a private balance and enqueues a public call to update the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn burn_private(from: AztecAddress, amount: u128, _nonce: Field) {
        _validate_from_private::<3>(self.context, from);

        self.internal._burn_private(from, amount);
    }

    /// @notice Burns tokens from a public balance
    /// @dev Burns tokens from a public balance and updates the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn burn_public(from: AztecAddress, amount: u128, _nonce: Field) {
        self.internal._validate_from_public(from);

        self.internal._burn_public(from, amount);
    }

    /// @notice Decreases the total supply by `amount`
    /// @param amount The amount of tokens to decrease the total supply by
    #[external("public")]
    #[only_self]
    fn decrease_total_supply_internal(amount: u128) {
        self.internal._decrease_total_supply(amount);
    }

    /// @notice Burns tokens from a public balance without validation
    /// @param from The address from which to burn the tokens
    /// @param amount The amount of tokens to burn
    #[external("public")]
    #[only_self]
    fn burn_public_internal(from: AztecAddress, amount: u128) {
        self.internal._burn_public(from, amount);
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

    /// @notice Decreases the private balance of `account` by `amount` and emits a private balance note with the change to account
    /// @param context The private context
    /// @param private_balances The storage pointer to the private balances
    /// @param account The address of the account to decrease the balance of
    /// @param amount The amount of tokens to decrease the balance by
    /// @param max_notes The maximum number of notes to process in a single call
    #[internal("private")]
    fn _decrease_private_balance(account: AztecAddress, amount: u128, max_notes: u32) {
        // Subtracts `amount` from the private balance of `account`
        let change = self.internal._subtract_balance(account, amount, max_notes);
        // Increases `change` to the private balance of `account`, and emits a private balance note to account
        self.storage.private_balances.at(account).add(change).deliver(
            MessageDelivery.CONSTRAINED_ONCHAIN,
        );
    }

    /// @notice Updates the given storage pointer `private_balances` to increase the private balance of `to` by `amount`
    /// @param private_balances The storage pointer to the private balances
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[internal("private")]
    fn _increase_private_balance(to: AztecAddress, amount: u128) {
        // Increases `amount` to the private balance of `to`, and emits a private balance note to `to` from `from`
        self.storage.private_balances.at(to).add(amount).deliver(MessageDelivery.CONSTRAINED_ONCHAIN);
    }

    /// @notice Updates the given storage pointer `public_balances` to increase the public balance of `to` by `amount`
    /// @param public_balances The storage pointer to the public balances
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[internal("public")]
    fn _increase_public_balance(to: AztecAddress, amount: u128) {
        // Read the current public balance of `to`, add `amount` to it,
        let new_balance = self.storage.public_balances.at(to).read() + amount;
        // write the result back to the storage
        self.storage.public_balances.at(to).write(new_balance);
    }

    /// @notice Updates the given storage pointer `public_balances` to decrease the public balance of `from` by `amount`
    /// @param public_balances The storage pointer to the public balances
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
    /// @param context The context of the public call
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param completer The address used to compute the validity commitment
    /// @param amount The amount of tokens to increase the balance of the commitment by
    #[internal("public")]
    fn _increase_commitment_balance(
        commitment: PartialUintNote,
        completer: AztecAddress,
        amount: u128,
    ) {
        commitment.complete(self.context, completer, amount);
    }

    /// @notice Subtracts balance from private balance
    /// @dev Subtracts amount from private balance and returns the change to the owner, recursively if necessary
    /// @param context The private context
    /// @param private_balances The storage pointer to the private balances
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @param max_notes The maximum number of notes to process in a single call
    /// @return The change to return to the owner
    #[internal("private")]
    fn _subtract_balance(account: AztecAddress, amount: u128, max_notes: u32) -> u128 {
        let subtracted = self.storage.private_balances.at(account).try_sub(amount, max_notes);
        if subtracted >= amount {
            // We have achieved our goal of nullifying notes that add up to more than amount, so we return the change.
            subtracted - amount
        } else {
            // Failing to subtract any amount means that the owner was unable to produce more notes that could be nullified.
            assert(subtracted > 0, "Balance too low");

            // try_sub failed to nullify enough notes to reach the target amount, so we compute the amount remaining
            // and try again.
            let remaining = amount - subtracted;

            self.call_self.recurse_subtract_balance_internal(account, remaining)
        }
    }

    /// @notice Increases the given storage pointer `total_supply` by `amount`
    /// @param total_supply The storage pointer to the total supply
    /// @param amount The amount of tokens to increase the total supply by
    #[internal("public")]
    fn _increase_total_supply(amount: u128) {
        let new_supply = self.storage.total_supply.read() + amount;
        self.storage.total_supply.write(new_supply);
    }

    /// @notice Decreases the given storage pointer `total_supply` by `amount`
    /// @param total_supply The storage pointer to the total supply
    /// @param amount The amount to decrease the total supply by
    #[internal("public")]
    fn _decrease_total_supply(amount: u128) {
        let new_supply = self.storage.total_supply.read() - amount;
        self.storage.total_supply.write(new_supply);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @param context The context of the private call
    /// @param private_balances The storage pointer to the private balances
    /// @param to The address of the recipient
    /// @param completer The address used to compute the validity commitment
    /// @return The partial note that can be used to execute the transfer/mint
    #[internal("private")]
    fn _initialize_transfer_commitment(
        to: AztecAddress,
        completer: AztecAddress,
    ) -> PartialUintNote {
        let commitment = UintNote::partial(
            to,
            self.storage.private_balances.get_storage_slot(),
            self.context,
            to,
            completer,
        );

        commitment
    }

    /// @notice Mints tokens to a public balance and increases the total supply
    /// @param public_balances The storage pointer to the public balances
    /// @param total_supply The storage pointer to the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[internal("public")]
    fn _mint_to_public(to: AztecAddress, amount: u128) {
        self.internal._increase_public_balance(to, amount);
        self.internal._increase_total_supply(amount);
    }

    /// @notice Mints tokens to a private balance and enqueues a public call to increase the total supply
    /// @param context The private context
    /// @param private_balances The storage pointer to the private balances
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[internal("private")]
    fn _mint_to_private(to: AztecAddress, amount: u128) {
        self.internal._increase_private_balance(to, amount);
        self.enqueue_self.increase_total_supply_internal(amount);
    }

    /// @notice Burns tokens from a public balance and decreases the total supply
    /// @param public_balances The storage pointer to the public balances
    /// @param total_supply The storage pointer to the total supply
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    #[internal("public")]
    fn _burn_public(from: AztecAddress, amount: u128) {
        self.internal._decrease_public_balance(from, amount);
        self.internal._decrease_total_supply(amount);
    }

    /// @notice Burns tokens from a private balance and enqueues a public call to decrease the total supply
    /// @param context The private context
    /// @param private_balances The storage pointer to the private balances
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    #[internal("private")]
    fn _burn_private(from: AztecAddress, amount: u128) {
        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);
        self.enqueue_self.decrease_total_supply_internal(amount);
    }

    /** ==========================================================
     * ===================  UPGRADEABLE  =========================
     * ======================================================== */

    /// @notice Upgrades the contract to a new contract class id
    /// @dev The upgrade authority must be set
    /// @dev The upgrade will only be effective after the upgrade delay has passed
    /// @param new_contract_class_id The new contract class id
    #[external("public")]
    fn upgrade_contract(new_contract_class_id: Field) {
        let upgrade_authority = self.storage.upgrade_authority.read();

        assert(!upgrade_authority.eq(AztecAddress::zero()), "upgrade authority not set");
        assert(self.msg_sender().unwrap().eq(upgrade_authority), "caller is not upgrade authority");

        self.call(ContractInstanceRegistry::at(CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS).update(
            ContractClassId::from_field(new_contract_class_id),
        ));
    }

    /** ==========================================================
     * ================== AUTH LIBRARIES =========================
     * ======================================================== */

    /// @notice Validates that the caller possesses authwit from the `from` address or the caller is the `from` address
    /// @param context The context of the private call
    /// @param from The address of the sender
    #[contract_library_method]
    fn _validate_from_private<let N: u32>(context: &mut PrivateContext, from: AztecAddress) {
        if (!from.eq(context.msg_sender().unwrap())) {
            assert_current_call_valid_authwit::<N>(context, from);
        }
    }

    /// @notice Validates that the caller possesses authwit from the `from` address or the caller is the `from` address
    /// @param context The context of the public call
    /// @param from The address of the sender
    #[internal("public")]
    fn _validate_from_public(from: AztecAddress) {
        if (!from.eq(self.msg_sender().unwrap())) {
            assert_current_call_valid_authwit_public(self.context, from);
        }
    }

    /** ==========================================================
     * ======================= VAULT =============================
     * ======================================================== */

    /* ====================== DEPOSIT ========================= */

    /// @notice Deposits the underlying asset from a public balance and receives shares to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn deposit_public_to_public(from: AztecAddress, to: AztecAddress, assets: u128, _nonce: Field) {
        self.internal._validate_from_public(from);

        // Calculate shares to mint
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);

        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));

        // Mint shares to the recipient
        self.internal._mint_to_public(to, shares);
    }

    /// @notice Deposits the underlying asset from a public balance and receives shares to a private balance
    /// @dev The shares are calculated based on the ratio (total_supply + offset) / (total_assets + 1) minus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by. Any asset excess is kept by the contract as yield.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares that should be minted to the recipient
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // Validate in public that `assets` is sufficient for the requested shares
        self.enqueue_self.validate_deposit_rate_internal(assets, shares);

        // Mint shares in private
        self.internal._mint_to_private(to, shares);

        // Take the assets from the sender
        self.enqueue(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a private balance
    /// @dev The shares are calculated based on the ratio (total_supply + offset) / (total_assets + 1) minus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by. Any asset excess is kept by the contract as yield.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares that should be minted to the recipient
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // Validate in public that `assets` is sufficient for the requested shares
        self.enqueue_self.validate_deposit_rate_internal(assets, shares);

        // Mint shares in private
        self.internal._mint_to_private(to, shares);

        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_private_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        // Calculate and mint shares to the recipient in public
        self.enqueue_self.issue_from_assets_internal(to, assets);

        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_private_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));
    }

    /// @notice Deposits the underlying asset from a public balance and receives shares to a private balance
    /// @dev min_shares is the amount of shares that will be minted immediately in private.
    ///      Any additional shares the recipient is entitled to, will be minted through a commitment once the call is executed publicly.
    ///      This additional amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param min_shares The amount of shares that should be minted to the recipient in private
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_public_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        min_shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // Increase recipient's private balance with `min_shares`
        self.internal._increase_private_balance(to, min_shares);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to mint outstanding shares to the recipient in public
        let partial_note = self.internal._initialize_transfer_commitment(to, self.address);

        // Mint any outstanding shares without revealing the recipient and updates the shares total supply
        // Reverts if min_shares is greater than allowed
        self.enqueue_self.settle_deposit_to_private_with_commitment_internal(
            partial_note.to_field(),
            assets,
            min_shares,
        );

        // Take the assets from the sender
        self.enqueue(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a private balance
    /// @dev min_shares is the amount of shares that will be minted immediately in private.
    ///      Any additional shares the recipient is entitled to, will be minted through a commitment once the call is executed publicly.
    ///      This additional amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param min_shares The amount of shares that should be minted to the recipient in private
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        min_shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // Increase recipient's private balance with `min_shares`
        self.internal._increase_private_balance(to, min_shares);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to mint outstanding shares to the recipient in public
        let partial_note = self.internal._initialize_transfer_commitment(to, self.address);

        // Mint any outstanding shares without revealing the recipient and updates the shares total supply
        // Reverts if min_shares is greater than allowed
        self.enqueue_self.settle_deposit_to_private_with_commitment_internal(
            partial_note.to_field(),
            assets,
            min_shares,
        );

        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_private_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));
    }

    /* ======================= ISSUE ========================== */

    /// @notice Issues exactly the requested shares to a public balance and receives the underlying asset from a public balance
    /// @dev max_assets is calculated based on the ratio (total_supply + offset) / (total_assets + 1) plus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by. Any excess assets the sender has transferred will be returned.
    ///      This excess amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn issue_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        self.internal._validate_from_public(from);

        // Calculate assets required
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_UP);

        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            max_assets,
            _nonce,
        ));

        // Refund
        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            // Reimburse the sender with any excess assets sent
            self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
                self.address,
                from,
                change,
                0,
            ));
        }

        // Mint shares to the recipient
        self.internal._mint_to_public(to, shares);
    }

    /// @notice Issues exactly the requested shares to a private balance and receives the underlying asset from a public balance
    /// @dev max_assets is calculated based on the ratio (total_supply + offset) / (total_assets + 1) plus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn issue_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // Take the assets from the sender
        self.enqueue(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            max_assets,
            _nonce,
        ));

        // Validate the amount of assets transferred and send back any excess
        self.enqueue_self.settle_issuance_from_public_internal(from, shares, max_assets);

        // Mint shares to the recipient
        self.internal._mint_to_private(to, shares);
    }

    /// @notice Issues exactly the requested shares to a public balance and receives the underlying asset from a private balance
    /// @dev Any excess assets the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn issue_private_to_public_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to refund excess assets to the sender in public
        let asset_commitment = self.call(Token::at(self.storage.asset.read())
            .initialize_transfer_commitment(from, self.address));

        // Take max_assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_private_to_public(
            from,
            self.address,
            max_assets,
            _nonce,
        ));

        // Validate max_assets in public and refund any excess to the sender with a commitment
        self.enqueue_self.settle_issuance_from_private_with_commitment(
            asset_commitment,
            shares,
            max_assets,
        );

        // Mint shares to recipient in public
        self.enqueue_self.mint_to_public_internal(to, shares);
    }

    /// @notice Issues exactly the requested shares to a private balance and receives the underlying asset from a private balance
    /// @dev Any excess assets the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    ///      To optimize calls to this method, consider setting max_assets to an exact sum of notes, so that change is not returned twice (in private and later via commitment)
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn issue_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to refund excess assets to the sender in public
        let asset_commitment = self.call(Token::at(self.storage.asset.read())
            .initialize_transfer_commitment(from, self.address));

        // Take max_assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_private_to_public(
            from,
            self.address,
            max_assets,
            _nonce,
        ));

        // Validate max_assets in public and refunds any excess to the sender with a commitment
        self.enqueue_self.settle_issuance_from_private_with_commitment(
            asset_commitment,
            shares,
            max_assets,
        );

        // Mint shares to recipient in private
        self.internal._mint_to_private(to, shares);
    }

    /* ====================== WITHDRAW ======================== */

    /// @notice Withdraws an amount of the underlying asset from a public balance to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn withdraw_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        _nonce: Field,
    ) {
        self.internal._validate_from_public(from);

        // Calculate shares to burn
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_UP);

        // Transfer the assets to the recipient
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));

        // Burn the sender's shares
        self.internal._burn_public(from, shares);
    }

    /// @notice Withdraws an amount of the underlying asset from a public balance to a private balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        // Calculate and burn the sender's shares
        self.enqueue_self.redeem_from_assets_internal(from, assets);

        // Transfer the assets to the recipient in private
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_private(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Withdraws an amount of the underlying asset from a private balance to a private balance
    /// @dev The shares are calculated with (total_supply + offset) / (total_assets + 1).
    ///      The ratio can only decrease or remain the same as time goes by. Any outstanding asset is kept by the contract as yield.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param shares The amount of shares to burn
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // Validate that the shares-assets ratio is correct
        self.enqueue_self.validate_withdrawal_rate_internal(assets, shares);

        // Burn shares from the sender in private
        self.internal._burn_private(from, shares);

        // Transfer the assets to the recipient in private
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_private(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Withdraws an amount of the underlying asset from a private balance to a public balance
    /// @dev max_shares is the amount of shares that will be burnt immediately in private.
    ///      Any excess shares the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    ///      To optimize calls to this method, consider setting max_shares to an exact sum of notes, so that change is not returned twice (in private and later via commitment)
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of underlying asset to withdraw
    /// @param max_shares The maximum amount of shares to burn
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_private_to_public_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        max_shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to refund excess shares to the sender in public
        let partial_note = self.internal._initialize_transfer_commitment(from, self.address);

        // Burn shares from the sender in private
        self.internal._decrease_private_balance(from, max_shares, INITIAL_TRANSFER_CALL_MAX_NOTES);

        // Burn the correct amount of shares
        // Any excess amount of shares is sent back to the sender via commitment
        // Reverts if the amount of shares required is greater than max_shares
        self.enqueue_self.settle_withdrawal_with_commitment_internal(
            partial_note.to_field(),
            assets,
            max_shares,
        );

        // Transfer the assets to the sender
        self.enqueue(Token::at(self.storage.asset.read()).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Withdraws an amount of the underlying asset from a private balance to a private balance
    /// @dev max_shares is the amount of shares that will be burnt immediately in private.
    ///      Any excess shares the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    ///      To optimize calls to this method, consider setting max_shares to an exact sum of notes, so that change is not returned twice (in private and later via commitment)
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of underlying asset to withdraw
    /// @param max_shares The maximum amount of shares to burn
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        max_shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to refund excess shares to the sender in public
        let partial_note = self.internal._initialize_transfer_commitment(from, self.address);

        // Burn shares from the sender in private
        self.internal._decrease_private_balance(from, max_shares, INITIAL_TRANSFER_CALL_MAX_NOTES);

        // Burn the correct amount of shares
        // Any excess amount of shares is sent back to the sender via commitment
        // Reverts if the amount of shares required is greater than max_shares
        self.enqueue_self.settle_withdrawal_with_commitment_internal(
            partial_note.to_field(),
            assets,
            max_shares,
        );

        // Transfer the assets to the recipient in private
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_private(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /* ======================= REDEEM ========================= */

    /// @notice Redeems an amount of the shares from a public balance to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn redeem_public_to_public(from: AztecAddress, to: AztecAddress, shares: u128, _nonce: Field) {
        self.internal._validate_from_public(from);

        // Calculate assets to redeem
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_DOWN);

        // Transfer the assets to the recipient
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));

        // Burn the sender's shares
        self.internal._burn_public(from, shares);
    }

    /// @notice Redeems an amount of the shares from a private balance to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn redeem_private_to_public(from: AztecAddress, to: AztecAddress, shares: u128, _nonce: Field) {
        _validate_from_private::<4>(self.context, from);

        // Burn shares and redeem public assets
        self.enqueue_self.settle_redemption_to_public_internal(to, shares);

        // Burn shares from the sender in private
        self.internal._burn_private(from, shares);
    }

    /// @notice Redeems an amount of the shares from a private balance to a private balance
    /// @dev min_assets is the amount of assets that will be transferred to the recipient immediately in private.
    ///      Any outstanding assets the recipient is entitled to, will be sent through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to burn
    /// @param min_assets The minimum amount of assets to withdraw, immediately in private
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn redeem_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        min_assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to transfer outstanding assets to the recipient in public
        let asset_commitment = self.call(Token::at(self.storage.asset.read())
            .initialize_transfer_commitment(to, self.address));

        // Transfers any outstanding assets without revealing the recipient
        // Reverts if min_assets is greater than allowed
        self.enqueue_self.settle_redemption_to_private_with_commitment(
            asset_commitment,
            shares,
            min_assets,
        );

        // Transfer min_assets to the recipient
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_private(
            self.address,
            to,
            min_assets,
            0,
        ));

        // Burn shares from the sender in private
        self.internal._burn_private(from, shares);
    }

    /// @notice Redeems an amount of the shares from a public balance to a private balance
    /// @dev min_assets is the amount of assets that will be transferred to the recipient immediately in private.
    ///      Any outstanding assets the recipient is entitled to, will be sent through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param min_assets The minimum amount of assets to withdraw, immediately in private
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn redeem_public_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        min_assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to transfer outstanding assets to the recipient in public
        let asset_commitment = self.call(Token::at(self.storage.asset.read())
            .initialize_transfer_commitment(to, self.address));

        // Transfers any outstanding assets without revealing the recipient
        // Reverts if min_assets is greater than allowed
        self.enqueue_self.settle_redemption_to_private_with_commitment(
            asset_commitment,
            shares,
            min_assets,
        );

        // Transfer min_assets to the recipient
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_private(
            self.address,
            to,
            min_assets,
            0,
        ));

        // Burn the shares being redeemed
        self.enqueue_self.burn_public_internal(from, shares);
    }

    /** ==========================================================
     * ==================== VAULT INTERNALS ======================
     * ======================================================== */

    /// @notice Burns shares held in public for a given amount of assets
    /// @param from The address of the sender
    /// @param assets The amount of assets to burn shares for
    #[external("public")]
    #[only_self]
    fn redeem_from_assets_internal(from: AztecAddress, assets: u128) {
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_UP);

        self.internal._burn_public(from, shares);
    }

    /// @notice Validates that the requested shares amount is valid for the given assets
    /// @param assets The amount of assets being withdrawn
    /// @param shares The amount of shares being burned
    #[external("public")]
    #[only_self]
    fn validate_withdrawal_rate_internal(assets: u128, shares: u128) {
        let total_assets = self.internal._total_assets();
        let min_shares = self.internal._convert_to_shares(assets, total_assets, ROUND_UP);

        assert(min_shares <= shares, "Insufficient shares burnt");
    }

    /// @notice Withdraws assets to a public balance for a given amount of shares
    /// @param to The address of the recipient
    /// @param shares The amount of shares being redeemed
    #[external("public")]
    #[only_self]
    fn settle_redemption_to_public_internal(to: AztecAddress, shares: u128) {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_DOWN);

        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Mints shares to a public balance for a given amount of assets
    /// @param to The address of the recipient
    /// @param assets The amount of assets being deposited
    #[external("public")]
    #[only_self]
    fn issue_from_assets_internal(to: AztecAddress, assets: u128) {
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);

        self.internal._mint_to_public(to, shares);
    }

    /// @notice Validates that the requested shares amount is valid for the deposited assets
    /// @param assets The amount of assets being deposited
    /// @param shares The amount of shares being issued
    #[external("public")]
    #[only_self]
    fn validate_deposit_rate_internal(assets: u128, shares: u128) {
        let total_assets = self.internal._total_assets();
        let max_shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);

        assert(shares <= max_shares, "Too many shares requested");
    }

    /// @notice Decreases shares total supply and refunds excess shares via commitment
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of assets being withdrawn
    /// @param max_shares The maximum amount of shares that should be redeemed
    #[external("public")]
    #[only_self]
    fn settle_withdrawal_with_commitment_internal(
        commitment: Field,
        assets: u128,
        max_shares: u128,
    ) {
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_UP);

        let surplus = max_shares - shares; // Reverts with underflow if invalid
        if surplus > 0 {
            self.internal._increase_commitment_balance(
                PartialUintNote::from_field(commitment),
                self.address,
                surplus,
            );
        }

        self.internal._decrease_total_supply(shares);
    }

    /// @notice Increases shares total supply and issues outstanding shares via commitment
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of assets being deposited
    /// @param min_shares The minimum amount of shares that should be issued
    #[external("public")]
    #[only_self]
    fn settle_deposit_to_private_with_commitment_internal(
        commitment: Field,
        assets: u128,
        min_shares: u128,
    ) {
        let total_assets = self.internal._total_assets();
        let max_shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);

        let outstanding_shares = max_shares - min_shares; // Reverts with underflow if invalid
        if outstanding_shares > 0 {
            self.internal._increase_commitment_balance(
                PartialUintNote::from_field(commitment),
                self.address,
                outstanding_shares,
            );
        }

        self.internal._increase_total_supply(max_shares);
    }

    /// @notice Refunds excess assets to the sender via commitment while validating the shares amount requested
    /// @param asset_commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of shares being issued
    /// @param max_assets The maximum amount of assets that should be deposited
    #[external("public")]
    #[only_self]
    fn settle_issuance_from_private_with_commitment(
        asset_commitment: Field,
        shares: u128,
        max_assets: u128,
    ) {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets - max_assets, ROUND_UP);

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            self.call(Token::at(self.storage.asset.read()).transfer_public_to_commitment(
                self.address,
                asset_commitment,
                change,
                0,
            ));
        }
    }

    /// @notice Validates share redemption rate and withdraws any outstanding assets via commitment
    /// @param asset_commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of shares being redeemed
    /// @param min_assets The minimum amount of assets that should be withdrawn
    #[external("public")]
    #[only_self]
    fn settle_redemption_to_private_with_commitment(
        asset_commitment: Field,
        shares: u128,
        min_assets: u128,
    ) {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_DOWN);

        let outstanding_assets = assets - min_assets; // Reverts with underflow if invalid
        if outstanding_assets > 0 {
            self.call(Token::at(self.storage.asset.read()).transfer_public_to_commitment(
                self.address,
                asset_commitment,
                outstanding_assets,
                0,
            ));
        }
    }

    /// @notice Validates issuance rate and refunds excess assets being deposited from a public balance
    /// @param from The address of the sender
    /// @param shares The amount of shares being issued
    /// @param max_assets The maximum amount of assets that should be deposited
    #[external("public")]
    #[only_self]
    fn settle_issuance_from_public_internal(from: AztecAddress, shares: u128, max_assets: u128) {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets - max_assets, ROUND_UP);

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
                self.address,
                from,
                change,
                0,
            ));
        }
    }

    /** ==========================================================
     * ================== VAULT LIBRARIES ========================
     * ======================================================== */

    /// @notice Returns the total amount of underlying assets held by the vault
    /// @param context The public context
    /// @param asset The storage pointer to the asset address
    /// @return The total amount of assets held by the vault
    #[internal("public")]
    fn _total_assets() -> u128 {
        let total_assets =
            self.view(Token::at(self.storage.asset.read()).balance_of_public(self.address));
        total_assets
    }

    /// @notice Converts an amount of assets to shares using the current exchange rate
    /// @param assets The amount of assets to convert
    /// @param total_assets The total amount of assets in the vault
    /// @param total_supply The storage pointer to the total supply of shares
    /// @param rounding The rounding direction (ROUND_UP or ROUND_DOWN)
    /// @return The equivalent amount of shares
    #[internal("public")]
    fn _convert_to_shares(assets: u128, total_assets: u128, rounding: bool) -> u128 {
        // TODO: handle overflow
        // TODO: optimize rounding
        let mul_term = assets * (self.storage.total_supply.read() + offset());
        let denominator = (total_assets + 1);
        let mut shares = mul_term / denominator;
        if (rounding == ROUND_UP) & (mul_term % denominator > 0) {
            shares = shares + 1;
        }
        shares
    }

    /// @notice Converts an amount of shares to assets using the current exchange rate
    /// @param shares The amount of shares to convert
    /// @param total_assets The total amount of assets in the vault
    /// @param total_supply The storage pointer to the total supply of shares
    /// @param rounding The rounding direction (ROUND_UP or ROUND_DOWN)
    /// @return The equivalent amount of assets
    #[internal("public")]
    fn _convert_to_assets(shares: u128, total_assets: u128, rounding: bool) -> u128 {
        // TODO: handle overflow
        // TODO: optimize rounding
        let mul_term = shares * (total_assets + 1);
        let denominator = (self.storage.total_supply.read() + offset());
        let mut assets = mul_term / denominator;
        if (rounding == ROUND_UP) & (mul_term % denominator > 0) {
            assets = assets + 1;
        }
        assets
    }

    /// @notice Offset that determines the rate of virtual shares to virtual assets in the vault, which itself determines the initial exchange rate.
    /// While not fully preventing inflation attacks, analysis shows that offset=1 makes it non-profitable even if an attacker is able to capture value from multiple user deposits,
    /// as a result of the value being captured by the virtual shares (out of the attacker's donation) matching the attacker's expected gains.
    /// With a larger offset, the attack becomes orders of magnitude more expensive than it is profitable.
    /// @return The offset value
    #[contract_library_method]
    fn offset() -> u128 {
        1
    }
}
