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
        context::{PrivateContext, PublicContext},
        macros::{functions::{external, initializer, internal, view}, storage::storage},
        messages::message_delivery::MessageDelivery,
        protocol_types::{
            address::AztecAddress,
            constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            contract_class_id::ContractClassId,
            traits::{FromField, ToField},
        },
        state_vars::{Map, public_immutable::PublicImmutable, public_mutable::PublicMutable},
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
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
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
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.decimals.initialize(decimals);
        storage.asset.initialize(asset);

        storage.upgrade_authority.initialize(upgrade_authority);
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
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.decimals.initialize(decimals);

        _mint_to_public(
            storage.public_balances,
            storage.total_supply,
            to,
            initial_supply,
        );

        storage.upgrade_authority.initialize(upgrade_authority);
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
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.decimals.initialize(decimals);

        storage.minter.initialize(minter);
        storage.upgrade_authority.initialize(upgrade_authority);
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
        _validate_from_private::<4>(&mut context, from);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        Token::at(context.this_address()).increase_public_balance_internal(to, amount).enqueue(
            &mut context,
        );
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
        _validate_from_private::<4>(&mut context, from);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        Token::at(context.this_address()).increase_public_balance_internal(to, amount).enqueue(
            &mut context,
        );

        // Only the sender will be able to complete the partial note
        let completer = context.msg_sender().unwrap();
        let commitment =
            _initialize_transfer_commitment(&mut context, storage.private_balances, to, completer);
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
        _validate_from_private::<4>(&mut context, from);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        _increase_private_balance(storage.private_balances, to, amount);
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
        _validate_from_private::<4>(&mut context, from);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        let completer = context.msg_sender().unwrap();
        PartialUintNote::from_field(commitment).complete_from_private(
            &mut context,
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
        _validate_from_private::<4>(&mut context, from);

        Token::at(context.this_address()).decrease_public_balance_internal(from, amount).enqueue(
            &mut context,
        );

        _increase_private_balance(storage.private_balances, to, amount);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @dev Returns a partial note that can be used to execute transfers/mints
    /// @param to The address of the recipient
    /// @param completer The address allowed to complete the partial note
    /// @return commitment The partial note initialized for the transfer/mint commitment
    #[external("private")]
    fn initialize_transfer_commitment(to: AztecAddress, completer: AztecAddress) -> Field {
        let commitment =
            _initialize_transfer_commitment(&mut context, storage.private_balances, to, completer);
        commitment.to_field()
    }

    /// @notice Recursively subtracts balance from private balance
    /// @dev Used to subtract private balances that exceed the max notes limit
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @return The change to return to the owner
    #[external("private")]
    #[internal]
    fn recurse_subtract_balance_internal(account: AztecAddress, amount: u128) -> u128 {
        _subtract_balance(
            &mut context,
            storage.private_balances,
            account,
            amount,
            RECURSIVE_TRANSFER_CALL_MAX_NOTES,
        )
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
        _validate_from_public(&mut context, from);

        _decrease_public_balance(storage.public_balances, from, amount);
        _increase_public_balance(storage.public_balances, to, amount);
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
        _validate_from_public(&mut context, from);

        _decrease_public_balance(storage.public_balances, from, amount);

        let completer = context.msg_sender().unwrap();
        _increase_commitment_balance(
            &mut context,
            PartialUintNote::from_field(commitment),
            completer,
            amount,
        );
    }

    /// @notice Increases the public balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[external("public")]
    #[internal]
    fn increase_public_balance_internal(to: AztecAddress, amount: u128) {
        _increase_public_balance(storage.public_balances, to, amount);
    }

    /// @notice Decreases the public balance of `from` by `amount`
    /// @param from The address of the sender
    /// @param amount The amount of tokens to decrease the balance by
    #[external("public")]
    #[internal]
    fn decrease_public_balance_internal(from: AztecAddress, amount: u128) {
        _decrease_public_balance(storage.public_balances, from, amount);
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
        storage.public_balances.at(owner).read()
    }

    /// @notice Returns the total supply of the token
    /// @return The total supply of the token
    #[external("public")]
    #[view]
    fn total_supply() -> u128 {
        storage.total_supply.read()
    }

    /// @notice Returns the name of the token
    /// @return The name of the token
    #[external("public")]
    #[view]
    fn name() -> FieldCompressedString {
        storage.name.read()
    }

    /// @notice Returns the symbol of the token
    /// @return The symbol of the token
    #[external("public")]
    #[view]
    fn symbol() -> FieldCompressedString {
        storage.symbol.read()
    }

    /// @notice Returns the decimals of the token
    /// @return The decimals of the token
    #[external("public")]
    #[view]
    fn decimals() -> u8 {
        storage.decimals.read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    /// @notice Returns the private balance of an account
    /// @param owner The address to query
    /// @return The private balance of the address
    #[external("utility")]
    unconstrained fn balance_of_private(owner: AztecAddress) -> u128 {
        storage.private_balances.at(owner).balance_of()
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
        _validate_minter(context.msg_sender().unwrap(), storage.minter.read());

        _mint_to_private(&mut context, storage.private_balances, to, amount);
    }

    /// @notice Mints tokens to an address publicly
    /// @dev Increases the public balance of `to` by `amount` and the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[external("public")]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        _validate_minter(context.msg_sender().unwrap(), storage.minter.read());

        _mint_to_public(storage.public_balances, storage.total_supply, to, amount);
    }

    /// @notice Finalizes a mint to a commitment
    /// @dev Finalizes a mint to a commitment and updates the total supply
    /// @param commitment The partial note representing the mint commitment (privacy entrance)
    /// @param amount The amount of tokens to mint
    #[external("public")]
    fn mint_to_commitment(commitment: Field, amount: u128) {
        let sender = context.msg_sender().unwrap();
        _validate_minter(sender, storage.minter.read());
        let completer = sender;
        _increase_total_supply(storage.total_supply, amount);
        _increase_commitment_balance(
            &mut context,
            PartialUintNote::from_field(commitment),
            completer,
            amount,
        );
    }

    /// @notice Internal function to increase the total supply by `amount`
    /// @param amount The amount to increase the total supply by
    #[external("public")]
    #[internal]
    fn increase_total_supply_internal(amount: u128) {
        _increase_total_supply(storage.total_supply, amount);
    }

    /// @notice Internal function to mint tokens to a public balance
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[external("public")]
    #[internal]
    fn mint_to_public_internal(to: AztecAddress, amount: u128) {
        _mint_to_public(storage.public_balances, storage.total_supply, to, amount);
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
        _validate_from_private::<3>(&mut context, from);

        _burn_private(&mut context, storage.private_balances, from, amount);
    }

    /// @notice Burns tokens from a public balance
    /// @dev Burns tokens from a public balance and updates the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn burn_public(from: AztecAddress, amount: u128, _nonce: Field) {
        _validate_from_public(&mut context, from);

        _burn_public(storage.public_balances, storage.total_supply, from, amount);
    }

    /// @notice Decreases the total supply by `amount`
    /// @param amount The amount of tokens to decrease the total supply by
    #[external("public")]
    #[internal]
    fn decrease_total_supply_internal(amount: u128) {
        _decrease_total_supply(storage.total_supply, amount);
    }

    /// @notice Burns tokens from a public balance without validation
    /// @param from The address from which to burn the tokens
    /// @param amount The amount of tokens to burn
    #[external("public")]
    #[internal]
    fn burn_public_internal(from: AztecAddress, amount: u128) {
        _burn_public(storage.public_balances, storage.total_supply, from, amount);
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
    #[contract_library_method]
    fn _decrease_private_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: u128,
        max_notes: u32,
    ) {
        // Subtracts `amount` from the private balance of `account`
        let change = _subtract_balance(context, private_balances, account, amount, max_notes);
        // Increases `change` to the private balance of `account`, and emits a private balance note to account
        private_balances.at(account).add(account, change).emit(
            account,
            MessageDelivery.CONSTRAINED_ONCHAIN,
        );
    }

    /// @notice Updates the given storage pointer `private_balances` to increase the private balance of `to` by `amount`
    /// @param private_balances The storage pointer to the private balances
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[contract_library_method]
    fn _increase_private_balance(
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        to: AztecAddress,
        amount: u128,
    ) {
        // Increases `amount` to the private balance of `to`, and emits a private balance note to `to` from `from`
        private_balances.at(to).add(to, amount).emit(to, MessageDelivery.CONSTRAINED_ONCHAIN);
    }

    /// @notice Updates the given storage pointer `public_balances` to increase the public balance of `to` by `amount`
    /// @param public_balances The storage pointer to the public balances
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[contract_library_method]
    fn _increase_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        to: AztecAddress,
        amount: u128,
    ) {
        // Read the current public balance of `to`, add `amount` to it,
        let new_balance = public_balances.at(to).read() + amount;
        // write the result back to the storage
        public_balances.at(to).write(new_balance);
    }

    /// @notice Updates the given storage pointer `public_balances` to decrease the public balance of `from` by `amount`
    /// @param public_balances The storage pointer to the public balances
    /// @param from The address of the account to decrease the balance of
    /// @param amount The amount of tokens to decrease the balance by
    #[contract_library_method]
    fn _decrease_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        amount: u128,
    ) {
        // read the current public balance of `from`, subtract `amount`
        let new_balance = public_balances.at(from).read() - amount;
        // update the public balance of `from` with the new balance
        public_balances.at(from).write(new_balance);
    }

    /// @notice Completes a partial note
    /// @dev Completes a partial note and increases the balance of the commitment by `amount`
    /// @param context The context of the public call
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param completer The address used to compute the validity commitment
    /// @param amount The amount of tokens to increase the balance of the commitment by
    #[contract_library_method]
    fn _increase_commitment_balance(
        context: &mut PublicContext,
        commitment: PartialUintNote,
        completer: AztecAddress,
        amount: u128,
    ) {
        commitment.complete(context, completer, amount);
    }

    /// @notice Subtracts balance from private balance
    /// @dev Subtracts amount from private balance and returns the change to the owner, recursively if necessary
    /// @param context The private context
    /// @param private_balances The storage pointer to the private balances
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @param max_notes The maximum number of notes to process in a single call
    /// @return The change to return to the owner
    #[contract_library_method]
    fn _subtract_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: u128,
        max_notes: u32,
    ) -> u128 {
        let subtracted = private_balances.at(account).try_sub(amount, max_notes);
        if subtracted >= amount {
            // We have achieved our goal of nullifying notes that add up to more than amount, so we return the change.
            subtracted - amount
        } else {
            // Failing to subtract any amount means that the owner was unable to produce more notes that could be nullified.
            assert(subtracted > 0, "Balance too low");

            // try_sub failed to nullify enough notes to reach the target amount, so we compute the amount remaining
            // and try again.
            let remaining = amount - subtracted;

            Token::at(context.this_address())
                .recurse_subtract_balance_internal(account, remaining)
                .call(context)
        }
    }

    /// @notice Increases the given storage pointer `total_supply` by `amount`
    /// @param total_supply The storage pointer to the total supply
    /// @param amount The amount of tokens to increase the total supply by
    #[contract_library_method]
    fn _increase_total_supply(total_supply: PublicMutable<u128, &mut PublicContext>, amount: u128) {
        let new_supply = total_supply.read() + amount;
        total_supply.write(new_supply);
    }

    /// @notice Decreases the given storage pointer `total_supply` by `amount`
    /// @param total_supply The storage pointer to the total supply
    /// @param amount The amount to decrease the total supply by
    #[contract_library_method]
    fn _decrease_total_supply(total_supply: PublicMutable<u128, &mut PublicContext>, amount: u128) {
        let new_supply = total_supply.read() - amount;
        total_supply.write(new_supply);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @param context The context of the private call
    /// @param private_balances The storage pointer to the private balances
    /// @param to The address of the recipient
    /// @param completer The address used to compute the validity commitment
    /// @return The partial note that can be used to execute the transfer/mint
    #[contract_library_method]
    fn _initialize_transfer_commitment(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        to: AztecAddress,
        completer: AztecAddress,
    ) -> PartialUintNote {
        let commitment = UintNote::partial(
            to,
            private_balances.at(to).set.storage_slot,
            context,
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
    #[contract_library_method]
    fn _mint_to_public(
        public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        total_supply: PublicMutable<u128, &mut PublicContext>,
        to: AztecAddress,
        amount: u128,
    ) {
        _increase_public_balance(public_balances, to, amount);
        _increase_total_supply(total_supply, amount);
    }

    /// @notice Mints tokens to a private balance and enqueues a public call to increase the total supply
    /// @param context The private context
    /// @param private_balances The storage pointer to the private balances
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[contract_library_method]
    fn _mint_to_private(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        to: AztecAddress,
        amount: u128,
    ) {
        _increase_private_balance(private_balances, to, amount);

        Token::at(context.this_address()).increase_total_supply_internal(amount).enqueue(context);
    }

    /// @notice Burns tokens from a public balance and decreases the total supply
    /// @param public_balances The storage pointer to the public balances
    /// @param total_supply The storage pointer to the total supply
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    #[contract_library_method]
    fn _burn_public(
        public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        total_supply: PublicMutable<u128, &mut PublicContext>,
        from: AztecAddress,
        amount: u128,
    ) {
        _decrease_public_balance(public_balances, from, amount);
        _decrease_total_supply(total_supply, amount);
    }

    /// @notice Burns tokens from a private balance and enqueues a public call to decrease the total supply
    /// @param context The private context
    /// @param private_balances The storage pointer to the private balances
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    #[contract_library_method]
    fn _burn_private(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress,
        amount: u128,
    ) {
        _decrease_private_balance(
            context,
            private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        Token::at(context.this_address()).decrease_total_supply_internal(amount).enqueue(context);
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
        let upgrade_authority = storage.upgrade_authority.read();

        assert(!upgrade_authority.eq(AztecAddress::zero()), "upgrade authority not set");
        assert(
            context.msg_sender().unwrap().eq(upgrade_authority),
            "caller is not upgrade authority",
        );

        ContractInstanceRegistry::at(CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS)
            .update(ContractClassId::from_field(new_contract_class_id))
            .call(&mut context);
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
    #[contract_library_method]
    unconstrained fn _validate_from_public(context: &mut PublicContext, from: AztecAddress) {
        if (!from.eq(context.msg_sender().unwrap())) {
            assert_current_call_valid_authwit_public(context, from);
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
        _validate_from_public(&mut context, from);

        // Calculate shares to mint
        let total_assets = _total_assets(&mut context, storage.asset);
        let shares = _convert_to_shares(assets, total_assets, storage.total_supply, ROUND_DOWN);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), assets, _nonce)
            .call(&mut context);

        // Mint shares to the recipient
        _mint_to_public(storage.public_balances, storage.total_supply, to, shares);
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
        _validate_from_private::<5>(&mut context, from);

        // Validate in public that `assets` is sufficient for the requested shares
        Token::at(context.this_address()).validate_deposit_rate_internal(assets, shares).enqueue(
            &mut context,
        );

        // Mint shares in private
        _mint_to_private(&mut context, storage.private_balances, to, shares);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), assets, _nonce)
            .enqueue(&mut context);
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
        _validate_from_private::<5>(&mut context, from);

        // Validate in public that `assets` is sufficient for the requested shares
        Token::at(context.this_address()).validate_deposit_rate_internal(assets, shares).enqueue(
            &mut context,
        );

        // Mint shares in private
        _mint_to_private(&mut context, storage.private_balances, to, shares);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), assets, _nonce)
            .call(&mut context);
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
        _validate_from_private::<4>(&mut context, from);

        // Calculate and mint shares to the recipient in public
        Token::at(context.this_address()).issue_from_assets_internal(to, assets).enqueue(
            &mut context,
        );

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), assets, _nonce)
            .call(&mut context);
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
        _validate_from_private::<5>(&mut context, from);

        // Increase recipient's private balance with `min_shares`
        _increase_private_balance(storage.private_balances, to, min_shares);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to mint outstanding shares to the recipient in public
        let partial_note = _initialize_transfer_commitment(
            &mut context,
            storage.private_balances,
            to,
            context.this_address(),
        );

        // Mint any outstanding shares without revealing the recipient and updates the shares total supply
        // Reverts if min_shares is greater than allowed
        Token::at(context.this_address())
            .settle_deposit_to_private_with_commitment_internal(
                partial_note.to_field(),
                assets,
                min_shares,
            )
            .enqueue(&mut context);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), assets, _nonce)
            .enqueue(&mut context);
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
        _validate_from_private::<5>(&mut context, from);

        // Increase recipient's private balance with `min_shares`
        _increase_private_balance(storage.private_balances, to, min_shares);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to mint outstanding shares to the recipient in public
        let partial_note = _initialize_transfer_commitment(
            &mut context,
            storage.private_balances,
            to,
            context.this_address(),
        );

        // Mint any outstanding shares without revealing the recipient and updates the shares total supply
        // Reverts if min_shares is greater than allowed
        Token::at(context.this_address())
            .settle_deposit_to_private_with_commitment_internal(
                partial_note.to_field(),
                assets,
                min_shares,
            )
            .enqueue(&mut context);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), assets, _nonce)
            .call(&mut context);
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
        _validate_from_public(&mut context, from);

        // Calculate assets required
        let total_assets = _total_assets(&mut context, storage.asset);
        let assets = _convert_to_assets(shares, total_assets, storage.total_supply, ROUND_UP);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), max_assets, _nonce)
            .call(&mut context);

        // Refund
        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            // Reimburse the sender with any excess assets sent
            Token::at(storage.asset.read())
                .transfer_public_to_public(context.this_address(), from, change, 0)
                .call(&mut context);
        }

        // Mint shares to the recipient
        _mint_to_public(storage.public_balances, storage.total_supply, to, shares);
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
        _validate_from_private::<5>(&mut context, from);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), max_assets, _nonce)
            .enqueue(&mut context);

        // Validate the amount of assets transferred and send back any excess
        Token::at(context.this_address())
            .settle_issuance_from_public_internal(from, shares, max_assets)
            .enqueue(&mut context);

        // Mint shares to the recipient
        _mint_to_private(&mut context, storage.private_balances, to, shares);
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
        _validate_from_private::<5>(&mut context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to refund excess assets to the sender in public
        let asset_commitment = Token::at(storage.asset.read())
            .initialize_transfer_commitment(from, context.this_address())
            .call(&mut context);

        // Take max_assets from the sender
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), max_assets, _nonce)
            .call(&mut context);

        // Validate max_assets in public and refund any excess to the sender with a commitment
        Token::at(context.this_address())
            .settle_issuance_from_private_with_commitment(asset_commitment, shares, max_assets)
            .enqueue(&mut context);

        // Mint shares to recipient in public
        Token::at(context.this_address()).mint_to_public_internal(to, shares).enqueue(&mut context);
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
        _validate_from_private::<5>(&mut context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to refund excess assets to the sender in public
        let asset_commitment = Token::at(storage.asset.read())
            .initialize_transfer_commitment(from, context.this_address())
            .call(&mut context);

        // Take max_assets from the sender
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), max_assets, _nonce)
            .call(&mut context);

        // Validate max_assets in public and refunds any excess to the sender with a commitment
        Token::at(context.this_address())
            .settle_issuance_from_private_with_commitment(asset_commitment, shares, max_assets)
            .enqueue(&mut context);

        // Mint shares to recipient in private
        _mint_to_private(&mut context, storage.private_balances, to, shares);
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
        _validate_from_public(&mut context, from);

        // Calculate shares to burn
        let total_assets = _total_assets(&mut context, storage.asset);
        let shares = _convert_to_shares(assets, total_assets, storage.total_supply, ROUND_UP);

        // Transfer the assets to the recipient
        Token::at(storage.asset.read())
            .transfer_public_to_public(context.this_address(), to, assets, 0)
            .call(&mut context);

        // Burn the sender's shares
        _burn_public(storage.public_balances, storage.total_supply, from, shares);
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
        _validate_from_private::<4>(&mut context, from);

        // Calculate and burn the sender's shares
        Token::at(context.this_address()).redeem_from_assets_internal(from, assets).enqueue(
            &mut context,
        );

        // Transfer the assets to the recipient in private
        Token::at(storage.asset.read())
            .transfer_public_to_private(context.this_address(), to, assets, 0)
            .call(&mut context);
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
        _validate_from_private::<5>(&mut context, from);

        // Validate that the shares-assets ratio is correct
        Token::at(context.this_address()).validate_withdrawal_rate_internal(assets, shares).enqueue(
            &mut context,
        );

        // Burn shares from the sender in private
        _burn_private(&mut context, storage.private_balances, from, shares);

        // Transfer the assets to the recipient in private
        Token::at(storage.asset.read())
            .transfer_public_to_private(context.this_address(), to, assets, 0)
            .call(&mut context);
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
        _validate_from_private::<5>(&mut context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to refund excess shares to the sender in public
        let partial_note = _initialize_transfer_commitment(
            &mut context,
            storage.private_balances,
            from,
            context.this_address(),
        );

        // Burn shares from the sender in private
        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            max_shares,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        // Burn the correct amount of shares
        // Any excess amount of shares is sent back to the sender via commitment
        // Reverts if the amount of shares required is greater than max_shares
        Token::at(context.this_address())
            .settle_withdrawal_with_commitment_internal(partial_note.to_field(), assets, max_shares)
            .enqueue(&mut context);

        // Transfer the assets to the sender
        Token::at(storage.asset.read())
            .transfer_public_to_public(context.this_address(), to, assets, 0)
            .enqueue(&mut context);
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
        _validate_from_private::<5>(&mut context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to refund excess shares to the sender in public
        let partial_note = _initialize_transfer_commitment(
            &mut context,
            storage.private_balances,
            from,
            context.this_address(),
        );

        // Burn shares from the sender in private
        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            max_shares,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        // Burn the correct amount of shares
        // Any excess amount of shares is sent back to the sender via commitment
        // Reverts if the amount of shares required is greater than max_shares
        Token::at(context.this_address())
            .settle_withdrawal_with_commitment_internal(partial_note.to_field(), assets, max_shares)
            .enqueue(&mut context);

        // Transfer the assets to the recipient in private
        Token::at(storage.asset.read())
            .transfer_public_to_private(context.this_address(), to, assets, 0)
            .call(&mut context);
    }

    /* ======================= REDEEM ========================= */

    /// @notice Redeems an amount of the shares from a public balance to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn redeem_public_to_public(from: AztecAddress, to: AztecAddress, shares: u128, _nonce: Field) {
        _validate_from_public(&mut context, from);

        // Calculate assets to redeem
        let total_assets = _total_assets(&mut context, storage.asset);
        let assets = _convert_to_assets(shares, total_assets, storage.total_supply, ROUND_DOWN);

        // Transfer the assets to the recipient
        Token::at(storage.asset.read())
            .transfer_public_to_public(context.this_address(), to, assets, 0)
            .call(&mut context);

        // Burn the sender's shares
        _burn_public(storage.public_balances, storage.total_supply, from, shares);
    }

    /// @notice Redeems an amount of the shares from a private balance to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn redeem_private_to_public(from: AztecAddress, to: AztecAddress, shares: u128, _nonce: Field) {
        _validate_from_private::<4>(&mut context, from);

        // Burn shares and redeem public assets
        Token::at(context.this_address()).settle_redemption_to_public_internal(to, shares).enqueue(
            &mut context,
        );

        // Burn shares from the sender in private
        _burn_private(&mut context, storage.private_balances, from, shares);
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
        _validate_from_private::<5>(&mut context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to transfer outstanding assets to the recipient in public
        let asset_commitment = Token::at(storage.asset.read())
            .initialize_transfer_commitment(to, context.this_address())
            .call(&mut context);

        // Transfers any outstanding assets without revealing the recipient
        // Reverts if min_assets is greater than allowed
        Token::at(context.this_address())
            .settle_redemption_to_private_with_commitment(asset_commitment, shares, min_assets)
            .enqueue(&mut context);

        // Transfer min_assets to the recipient
        Token::at(storage.asset.read())
            .transfer_public_to_private(context.this_address(), to, min_assets, 0)
            .call(&mut context);

        // Burn shares from the sender in private
        _burn_private(&mut context, storage.private_balances, from, shares);
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
        _validate_from_private::<5>(&mut context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to transfer outstanding assets to the recipient in public
        let asset_commitment = Token::at(storage.asset.read())
            .initialize_transfer_commitment(to, context.this_address())
            .call(&mut context);

        // Transfers any outstanding assets without revealing the recipient
        // Reverts if min_assets is greater than allowed
        Token::at(context.this_address())
            .settle_redemption_to_private_with_commitment(asset_commitment, shares, min_assets)
            .enqueue(&mut context);

        // Transfer min_assets to the recipient
        Token::at(storage.asset.read())
            .transfer_public_to_private(context.this_address(), to, min_assets, 0)
            .call(&mut context);

        // Burn the shares being redeemed
        Token::at(context.this_address()).burn_public_internal(from, shares).enqueue(&mut context);
    }

    /** ==========================================================
     * ==================== VAULT INTERNALS ======================
     * ======================================================== */

    /// @notice Burns shares held in public for a given amount of assets
    /// @param from The address of the sender
    /// @param assets The amount of assets to burn shares for
    #[external("public")]
    #[internal]
    fn redeem_from_assets_internal(from: AztecAddress, assets: u128) {
        let total_assets = _total_assets(&mut context, storage.asset);
        let shares = _convert_to_shares(assets, total_assets, storage.total_supply, ROUND_UP);

        _burn_public(storage.public_balances, storage.total_supply, from, shares);
    }

    /// @notice Validates that the requested shares amount is valid for the given assets
    /// @param assets The amount of assets being withdrawn
    /// @param shares The amount of shares being burned
    #[external("public")]
    #[internal]
    fn validate_withdrawal_rate_internal(assets: u128, shares: u128) {
        let total_assets = _total_assets(&mut context, storage.asset);
        let min_shares = _convert_to_shares(assets, total_assets, storage.total_supply, ROUND_UP);

        assert(min_shares <= shares, "Insufficient shares burnt");
    }

    /// @notice Withdraws assets to a public balance for a given amount of shares
    /// @param to The address of the recipient
    /// @param shares The amount of shares being redeemed
    #[external("public")]
    #[internal]
    fn settle_redemption_to_public_internal(to: AztecAddress, shares: u128) {
        let total_assets = _total_assets(&mut context, storage.asset);
        let assets = _convert_to_assets(shares, total_assets, storage.total_supply, ROUND_DOWN);

        Token::at(storage.asset.read())
            .transfer_public_to_public(context.this_address(), to, assets, 0)
            .call(&mut context);
    }

    /// @notice Mints shares to a public balance for a given amount of assets
    /// @param to The address of the recipient
    /// @param assets The amount of assets being deposited
    #[external("public")]
    #[internal]
    fn issue_from_assets_internal(to: AztecAddress, assets: u128) {
        let total_assets = _total_assets(&mut context, storage.asset);
        let shares = _convert_to_shares(assets, total_assets, storage.total_supply, ROUND_DOWN);

        _mint_to_public(storage.public_balances, storage.total_supply, to, shares);
    }

    /// @notice Validates that the requested shares amount is valid for the deposited assets
    /// @param assets The amount of assets being deposited
    /// @param shares The amount of shares being issued
    #[external("public")]
    #[internal]
    fn validate_deposit_rate_internal(assets: u128, shares: u128) {
        let total_assets = _total_assets(&mut context, storage.asset);
        let max_shares = _convert_to_shares(assets, total_assets, storage.total_supply, ROUND_DOWN);

        assert(shares <= max_shares, "Too many shares requested");
    }

    /// @notice Decreases shares total supply and refunds excess shares via commitment
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of assets being withdrawn
    /// @param max_shares The maximum amount of shares that should be redeemed
    #[external("public")]
    #[internal]
    fn settle_withdrawal_with_commitment_internal(
        commitment: Field,
        assets: u128,
        max_shares: u128,
    ) {
        let total_assets = _total_assets(&mut context, storage.asset);
        let shares = _convert_to_shares(assets, total_assets, storage.total_supply, ROUND_UP);

        let surplus = max_shares - shares; // Reverts with underflow if invalid
        if surplus > 0 {
            _increase_commitment_balance(
                &mut context,
                PartialUintNote::from_field(commitment),
                context.this_address(),
                surplus,
            );
        }

        _decrease_total_supply(storage.total_supply, shares);
    }

    /// @notice Increases shares total supply and issues outstanding shares via commitment
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of assets being deposited
    /// @param min_shares The minimum amount of shares that should be issued
    #[external("public")]
    #[internal]
    fn settle_deposit_to_private_with_commitment_internal(
        commitment: Field,
        assets: u128,
        min_shares: u128,
    ) {
        let total_assets = _total_assets(&mut context, storage.asset);
        let max_shares = _convert_to_shares(assets, total_assets, storage.total_supply, ROUND_DOWN);

        let outstanding_shares = max_shares - min_shares; // Reverts with underflow if invalid
        if outstanding_shares > 0 {
            _increase_commitment_balance(
                &mut context,
                PartialUintNote::from_field(commitment),
                context.this_address(),
                outstanding_shares,
            );
        }

        _increase_total_supply(storage.total_supply, max_shares);
    }

    /// @notice Refunds excess assets to the sender via commitment while validating the shares amount requested
    /// @param asset_commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of shares being issued
    /// @param max_assets The maximum amount of assets that should be deposited
    #[external("public")]
    #[internal]
    fn settle_issuance_from_private_with_commitment(
        asset_commitment: Field,
        shares: u128,
        max_assets: u128,
    ) {
        let total_assets = _total_assets(&mut context, storage.asset);
        let assets = _convert_to_assets(
            shares,
            total_assets - max_assets,
            storage.total_supply,
            ROUND_UP,
        );

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            Token::at(storage.asset.read())
                .transfer_public_to_commitment(context.this_address(), asset_commitment, change, 0)
                .call(&mut context);
        }
    }

    /// @notice Validates share redemption rate and withdraws any outstanding assets via commitment
    /// @param asset_commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of shares being redeemed
    /// @param min_assets The minimum amount of assets that should be withdrawn
    #[external("public")]
    #[internal]
    fn settle_redemption_to_private_with_commitment(
        asset_commitment: Field,
        shares: u128,
        min_assets: u128,
    ) {
        let total_assets = _total_assets(&mut context, storage.asset);
        let assets = _convert_to_assets(shares, total_assets, storage.total_supply, ROUND_DOWN);

        let outstanding_assets = assets - min_assets; // Reverts with underflow if invalid
        if outstanding_assets > 0 {
            Token::at(storage.asset.read())
                .transfer_public_to_commitment(
                    context.this_address(),
                    asset_commitment,
                    outstanding_assets,
                    0,
                )
                .call(&mut context);
        }
    }

    /// @notice Validates issuance rate and refunds excess assets being deposited from a public balance
    /// @param from The address of the sender
    /// @param shares The amount of shares being issued
    /// @param max_assets The maximum amount of assets that should be deposited
    #[external("public")]
    #[internal]
    fn settle_issuance_from_public_internal(from: AztecAddress, shares: u128, max_assets: u128) {
        let total_assets = _total_assets(&mut context, storage.asset);
        let assets = _convert_to_assets(
            shares,
            total_assets - max_assets,
            storage.total_supply,
            ROUND_UP,
        );

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            Token::at(storage.asset.read())
                .transfer_public_to_public(context.this_address(), from, change, 0)
                .call(&mut context);
        }
    }

    /** ==========================================================
     * ================== VAULT LIBRARIES ========================
     * ======================================================== */

    /// @notice Returns the total amount of underlying assets held by the vault
    /// @param context The public context
    /// @param asset The storage pointer to the asset address
    /// @return The total amount of assets held by the vault
    #[contract_library_method]
    unconstrained fn _total_assets(
        context: &mut PublicContext,
        asset: PublicImmutable<AztecAddress, &mut PublicContext>,
    ) -> u128 {
        let total_assets =
            Token::at(asset.read()).balance_of_public(context.this_address()).view(context);
        total_assets
    }

    /// @notice Converts an amount of assets to shares using the current exchange rate
    /// @param assets The amount of assets to convert
    /// @param total_assets The total amount of assets in the vault
    /// @param total_supply The storage pointer to the total supply of shares
    /// @param rounding The rounding direction (ROUND_UP or ROUND_DOWN)
    /// @return The equivalent amount of shares
    #[contract_library_method]
    fn _convert_to_shares(
        assets: u128,
        total_assets: u128,
        total_supply: PublicMutable<u128, &mut PublicContext>,
        rounding: bool,
    ) -> u128 {
        // TODO: handle overflow
        // TODO: optimize rounding
        let mul_term = assets * (total_supply.read() + offset());
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
    #[contract_library_method]
    fn _convert_to_assets(
        shares: u128,
        total_assets: u128,
        total_supply: PublicMutable<u128, &mut PublicContext>,
        rounding: bool,
    ) -> u128 {
        // TODO: handle overflow
        // TODO: optimize rounding
        let mul_term = shares * (total_assets + 1);
        let denominator = (total_supply.read() + offset());
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
