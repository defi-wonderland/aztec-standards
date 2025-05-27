pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract Token {
    // aztec library
    use aztec::{
        context::PrivateContext,
        macros::{
            functions::{initializer, internal, private, public, utility, view},
            storage::storage,
        },
        prelude::{AztecAddress, Map, PublicContext, PublicImmutable, PublicMutable},
    };
    // authorized witness library
    use authwit::auth::{
        assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
    };
    // note library
    use uint_note::uint_note::{PartialUintNote, UintNote};
    // compression library
    use compressed_string::FieldCompressedString;
    // encryption library
    use aztec::messages::logs::note::encode_and_encrypt_note;
    // balance library
    use balance_set::balance_set::BalanceSet;

    // gas-optimized max notes for initial transfer call
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    // max notes transfer for recursive transfer call if initial max notes are exceeded
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

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
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<u128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
        asset: PublicImmutable<AztecAddress, Context>,
    }

    /// @notice Initializes the token with an asset
    /// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param asset The asset of the token
    #[public]
    #[initializer]
    fn constructor_with_asset(name: str<31>, symbol: str<31>, decimals: u8, asset: AztecAddress) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.decimals.initialize(decimals);
        storage.asset.initialize(asset);
    }

    /// @notice Initializes the token with an initial supply
    /// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param initial_supply The initial supply of the token
    /// @param to The address to mint the initial supply to
    #[public]
    #[initializer]
    fn constructor_with_initial_supply(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        initial_supply: u128,
        to: AztecAddress,
    ) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.decimals.initialize(decimals);

        _increase_public_balance(storage.public_balances, to, initial_supply);
        _increase_total_supply(storage.total_supply, initial_supply);
    }

    /// @notice Initializes the token with a minter
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param minter The address of the minter
    #[public]
    #[initializer]
    fn constructor_with_minter(name: str<31>, symbol: str<31>, decimals: u8, minter: AztecAddress) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.decimals.initialize(decimals);

        storage.minter.initialize(minter);
    }

    /** ==========================================================
    * ========================= PRIVATE =========================
    * ======================================================== */

    /// @notice Transfer tokens from private balance to public balance
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param nonce The nonce used for authwitness
    #[private]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);

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

    /// @notice Transfer tokens from private balance to public balance with a commitment
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, enqueues a public call, and returns a partial note
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param nonce The nonce used for authwitness
    /// @return commitment The partial note utilized for the transfer commitment (privacy entrance)
    #[private]
    fn transfer_private_to_public_with_commitment(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        nonce: Field,
    ) -> PartialUintNote {
        _validate_from_private(&mut context, from, nonce);

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

        let commitment =
            _initialize_transfer_commitment(&mut context, storage.private_balances, from, to);
        commitment
    }

    /// @notice Transfer tokens from private balance to another private balance
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and sends a note to the recipient
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param nonce The nonce used for authwitness
    #[private]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        _increase_private_balance(&mut context, storage.private_balances, from, to, amount);
    }

    /// @notice Transfer tokens from private balance to the recipient commitment (recipient must create a commitment first)
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
    /// @param from The address of the sender
    /// @param amount The amount of tokens to transfer
    /// @param commitment The partial note representing the commitment (privacy entrance that the recipient shares with the sender)
    /// @param nonce The nonce used for authwitness
    #[private]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        amount: u128,
        commitment: PartialUintNote,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        Token::at(context.this_address())
            .increase_commitment_balance_internal(commitment, amount)
            .enqueue(&mut context);
    }

    /// @notice Transfer tokens from public balance to private balance
    /// @dev Enqueues a public call to decrease account balance and emits a new note with balance difference
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param nonce The nonce used for authwitness
    #[private]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);

        Token::at(context.this_address()).decrease_public_balance_internal(from, amount).enqueue(
            &mut context,
        );

        _increase_private_balance(&mut context, storage.private_balances, from, to, amount);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @dev Returns a partial note that can be used to execute transfers/mints
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @return commitment The partial note initialized for the transfer/mint commitment
    #[private]
    fn initialize_transfer_commitment(from: AztecAddress, to: AztecAddress) -> PartialUintNote {
        _initialize_transfer_commitment(&mut context, storage.private_balances, from, to)
    }

    /// @notice Recursively subtracts balance from commitment
    /// @dev Used to subtract balances that exceed the max notes limit
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @return The change to return to the owner
    #[private]
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
    /// @param nonce The nonce used for authwitness
    #[public]
    fn transfer_public_to_public(from: AztecAddress, to: AztecAddress, amount: u128, nonce: Field) {
        _validate_from_public(&mut context, from, nonce);

        _decrease_public_balance(storage.public_balances, from, amount);
        _increase_public_balance(storage.public_balances, to, amount);
    }

    /// @notice Finalizes a transfer of token `amount` from public balance of `from` to a commitment of `to`
    /// @dev The transfer must be prepared by calling `initialize_transfer_commitment` first and the resulting
    /// `commitment` must be passed as an argument to this function
    /// @param from The address of the sender
    /// @param amount The amount of tokens to transfer
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param nonce The nonce used for authwitness
    #[public]
    fn transfer_public_to_commitment(
        from: AztecAddress,
        amount: u128,
        commitment: PartialUintNote,
        nonce: Field,
    ) {
        _validate_from_public(&mut context, from, nonce);

        _decrease_public_balance(storage.public_balances, from, amount);
        _increase_commitment_balance(&mut context, commitment, amount);
    }

    /// @notice Stores a partial note in storage
    /// @dev Used to store the commitment (privacy entrance)
    /// @param slot The partial note to store
    #[public]
    #[internal]
    fn store_commitment_in_storage_internal(slot: PartialUintNote) {
        _store_commitment_in_storage(&mut context, slot);
    }

    /// @notice Increases the public balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[public]
    #[internal]
    fn increase_public_balance_internal(to: AztecAddress, amount: u128) {
        _increase_public_balance(storage.public_balances, to, amount);
    }

    /// @notice Decreases the public balance of `from` by `amount`
    /// @param from The address of the sender
    /// @param amount The amount of tokens to decrease the balance by
    #[public]
    #[internal]
    fn decrease_public_balance_internal(from: AztecAddress, amount: u128) {
        _decrease_public_balance(storage.public_balances, from, amount);
    }

    /// @notice Increases the balance of the commitment by `amount`
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param amount The amount of tokens to increase the balance by
    #[public]
    #[internal]
    fn increase_commitment_balance_internal(commitment: PartialUintNote, amount: u128) {
        _increase_commitment_balance(&mut context, commitment, amount);
    }

    /** ==========================================================
    * ====================== VIEW FUNCTIONS =====================
    * ======================================================== */

    /// @notice Returns the public balance of `owner`
    /// @param owner The address of the owner
    /// @return The balance of the public balance of `owner`
    #[public]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> u128 {
        storage.public_balances.at(owner).read()
    }

    /// @notice Returns the total supply of the token
    /// @return The total supply of the token
    #[public]
    #[view]
    fn total_supply() -> u128 {
        storage.total_supply.read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */
    #[utility]
    unconstrained fn balance_of_private(owner: AztecAddress) -> u128 {
        storage.private_balances.at(owner).balance_of()
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    /// @notice Mints tokens to a commitment
    /// @dev Mints tokens to a commitment and enqueues a public call to increase the total supply
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[private]
    fn mint_to_private(from: AztecAddress, to: AztecAddress, amount: u128) {
        _validate_minter(context.msg_sender(), storage.minter.read());

        _increase_private_balance(&mut context, storage.private_balances, from, to, amount);

        // Enqueue call to increase total supply
        Token::at(context.this_address()).increase_total_supply_internal(amount).enqueue(
            &mut context,
        );
    }

    /// @notice Mints tokens to a public balance
    /// @dev Increases the public balance of `to` by `amount` and the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[public]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        _validate_minter(context.msg_sender(), storage.minter.read());

        _increase_public_balance(storage.public_balances, to, amount);
        _increase_total_supply(storage.total_supply, amount);
    }

    /// @notice Finalizes a mint to a commitment
    /// @dev Finalizes a mint to a commitment and updates the total supply
    /// @param amount The amount of tokens to mint
    /// @param commitment The partial note representing the mint commitment (privacy entrance)
    #[public]
    fn mint_to_commitment(amount: u128, commitment: PartialUintNote) {
        _validate_minter(context.msg_sender(), storage.minter.read());

        _increase_total_supply(storage.total_supply, amount);
        _increase_commitment_balance(&mut context, commitment, amount);
    }

    #[public]
    #[internal]
    fn increase_total_supply_internal(amount: u128) {
        _increase_total_supply(storage.total_supply, amount);
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns tokens from a commitment
    /// @dev Burns tokens from a commitment and enqueues a public call to update the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param nonce The nonce used for authwitness
    #[private]
    fn burn_private(from: AztecAddress, amount: u128, nonce: Field) {
        _validate_from_private(&mut context, from, nonce);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        Token::at(context.this_address()).decrease_total_supply_internal(amount).enqueue(
            &mut context,
        );
    }

    /// @notice Burns tokens from a public balance
    /// @dev Burns tokens from a public balance and updates the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param nonce The nonce used for authwitness
    #[public]
    fn burn_public(from: AztecAddress, amount: u128, nonce: Field) {
        _validate_from_public(&mut context, from, nonce);

        _decrease_public_balance(storage.public_balances, from, amount);
        _decrease_total_supply(storage.total_supply, amount);
    }

    /// @notice Decreases the total supply by `amount`
    /// @param amount The amount of tokens to decrease the total supply by
    #[public]
    #[internal]
    fn decrease_total_supply_internal(amount: u128) {
        _decrease_total_supply(storage.total_supply, amount);
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// Validates that the caller is the minter
    #[contract_library_method]
    fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }

    /// Decreases the private balance of `account` by `amount` and emits a private balance note with the change to account
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
        private_balances.at(account).add(account, change).emit(encode_and_encrypt_note(
            context,
            account,
            account,
        ));
    }

    /// @notice Updates the given storage pointer `private_balances` to increase the private balance of `to` by `amount`
    /// @param private_balances The storage pointer to the private balances
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[contract_library_method]
    fn _increase_private_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
    ) {
        // Increases `amount` to the private balance of `to`, and emits a private balance note to `to` from `from`
        private_balances.at(to).add(to, amount).emit(encode_and_encrypt_note(context, to, from));
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
    /// @param amount The amount of tokens to increase the balance of the commitment by
    #[contract_library_method]
    fn _increase_commitment_balance(
        context: &mut PublicContext,
        commitment: PartialUintNote,
        amount: u128,
    ) {
        // We verify that the partial note we're completing is valid (i.e. it uses the correct state variable's storage
        // slot, and it is internally consistent). We *could* clear the storage since each partial note should only be
        // used once, but since the AVM offers no gas refunds for doing so this would just make the transaction be more
        // expensive.
        assert(context.storage_read(commitment.commitment()), "Invalid commitment");
        commitment.complete(amount, context);
    }

    /// @notice Subtracts balance from commitment
    /// @dev Subtracts amount from commitment and returns the change to the owner, recursively if necessary
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
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
        // Failing to subtract any amount means that the owner was unable to produce more notes that could be nullified.
        assert(subtracted > 0, "Balance too low");
        if subtracted >= amount {
            // We have achieved our goal of nullifying notes that add up to more than amount, so we return the change.
            subtracted - amount
        } else {
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

    /// @notice Stores a partial note in storage
    /// @param context The context of the public call
    /// @param commitment The partial note to store
    #[contract_library_method]
    fn _store_commitment_in_storage(context: &mut PublicContext, commitment: PartialUintNote) {
        context.storage_write(commitment.commitment(), true);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @param context The context of the private call
    /// @param private_balances The storage pointer to the private balances
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @return The partial note that can be used to execute the transfer/mint
    #[contract_library_method]
    fn _initialize_transfer_commitment(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
    ) -> PartialUintNote {
        let commitment = UintNote::partial(
            to,
            private_balances.at(to).set.storage_slot,
            context,
            to,
            from,
        );

        // We can't simply return the partial note because we won't be able to later on verify that it was created
        // correctly (e.g. that the storage slot corresponds to the owner, and that we're using the balance set and not
        // another state variable) once this information is hidden in the partial note commitment. We therefore store
        // the partial note in our own public storage, so that we can later check that we're only completing correctly
        // created partial notes.
        Token::at(context.this_address()).store_commitment_in_storage_internal(commitment).enqueue(
            context,
        );
        commitment
    }

    /** ==========================================================
     * ================== AUTH LIBRARIES =========================
     * ======================================================== */

    /// @notice Validates that the caller possesses authwit from the `from` address or the caller is the `from` address
    /// @dev If the caller is the `from` address, the nonce must be 0
    /// @param context The context of the private call
    /// @param from The address of the sender
    /// @param nonce The nonce of the transaction
    #[contract_library_method]
    fn _validate_from_private(context: &mut PrivateContext, from: AztecAddress, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }

    /// @notice Validates that the caller possesses authwit from the `from` address or the caller is the `from` address
    /// @dev If the caller is the `from` address, the nonce must be 0
    /// @param context The context of the public call
    /// @param from The address of the sender
    /// @param nonce The nonce of the transaction
    #[contract_library_method]
    unconstrained fn _validate_from_public(
        context: &mut PublicContext,
        from: AztecAddress,
        nonce: Field,
    ) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }

    /** ==========================================================
     * ================== VAULT ==================================
     * ======================================================== */

    /** ==========================================================
     * ================== DEPOSIT ================================
     * ======================================================== */

    /// @notice Deposits the underlying asset from a public balance and receives shares to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param nonce The nonce used for authwitness
    #[public]
    fn deposit_public_to_public(from: AztecAddress, to: AztecAddress, assets: u128, nonce: Field) {
        let total_assets = Token::at(storage.asset.read())
            .balance_of_public(context.this_address())
            .view(&mut context);
        let shares = convertToShares(assets, total_assets, storage.total_supply.read());

        // Take the assets from the caller
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), assets, nonce)
            .call(&mut context);

        // Mint shares to the recipient
        _increase_public_balance(storage.public_balances, to, shares);
        _increase_total_supply(storage.total_supply, shares);
    }

    /// @notice Deposits the underlying asset from a public balance and receives shares to a private balance
    /// @dev The shares is calculated based on the ratio (total_supply + 1) / (total_assets + 1) minus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param shares The minimum amount of shares that should be minted to the recipient
    /// @param nonce The nonce used for authwitness
    #[private]
    fn deposit_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        nonce: Field,
    ) {
        _increase_private_balance(&mut context, storage.private_balances, from, to, shares);

        // mint shares to the recipient in public
        Token::at(context.this_address()).mint_private_shares_internal(assets, shares).enqueue(
            &mut context,
        );

        // Take the asset from the caller
        // Called after minting shares so that mint_private_shares_internal computes the amount of shares based on previous state.
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), assets, nonce)
            .enqueue(&mut context);
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a private balance
    /// @dev The shares are calculated based on the ratio (total_supply + 1) / (total_assets + 1) minus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares that should be minted to the recipient
    /// @param nonce The nonce used for authwitness
    #[private]
    fn deposit_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        nonce: Field,
    ) {
        _increase_private_balance(&mut context, storage.private_balances, from, to, shares);

        // mint shares to the recipient in public
        Token::at(context.this_address()).mint_private_shares_internal(assets, min_shares).enqueue(
            &mut context,
        );

        // Take the asset from the caller
        // Called after minting shares so that mint_private_shares_internal computes the amount of shares based on previous state.
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), assets, nonce)
            .call(&mut context);
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a public balance
    /// @dev The expected_ratio is calculated with (total_supply + 1) / (total_assets + 1) and is the ratio the user will get
    ///      when depositing assets. This ratio can only be lower than or equal to the actual ratio in public.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param nonce The nonce used for authwitness
    #[private]
    fn deposit_private_to_public(from: AztecAddress, to: AztecAddress, assets: u128, nonce: Field) {
        // mint shares to the recipient in public
        Token::at(context.this_address()).mint_shares_internal(to, assets).enqueue(&mut context);

        // Take the assets from the caller.
        // Called after minting shares so that mint_shares_internal computes the amount of shares based on previous state.
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), assets, nonce)
            .call(&mut context);
    }

    /// @notice Deposits the underlying asset from a public balance and receives shares to a private balance
    /// @dev min_shares is the amount of shares that will be minted immediately in private.
    ///      Any additional shares the caller is entitled to, will be minted through a commitment once the call is executed publicly.
    ///      This additional amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param min_shares The minimum amount of shares that should be minted to the recipient
    /// @param nonce The nonce used for authwitness
    #[private]
    fn deposit_public_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        min_shares: u128,
        nonce: Field,
    ) {
        _increase_private_balance(&mut context, storage.private_balances, from, to, min_shares);

        // TODO: do we actually need to emit the partial note log, emitted inside uint_note::partial?
        let commitment =
            _initialize_transfer_commitment(&mut context, storage.private_balances, from, to);

        // Mint shares without revealing the recipient
        Token::at(context.this_address())
            .mint_shares_with_commitment_internal(commitment, assets, min_shares)
            .enqueue(&mut context);

        // Take the asset from the caller
        // Called after minting shares so that mint_shares_with_commitment_internal computes the amount of shares based on previous state.
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), assets, nonce)
            .enqueue(&mut context);
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a private balance
    /// @dev min_shares is the amount of shares that will be minted immediately in private.
    ///      Any additional shares the caller is entitled to, will be minted through a commitment once the call is executed publicly.
    ///      This additional amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param min_shares The amount of shares that should be minted to the recipient in private
    /// @param nonce The nonce used for authwitness
    #[private]
    fn deposit_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        min_shares: u128,
        nonce: Field,
    ) {
        _increase_private_balance(&mut context, storage.private_balances, from, to, min_shares);

        // TODO: do we actually need to emit the partial note log, emitted inside uint_note::partial?
        let commitment =
            _initialize_transfer_commitment(&mut context, storage.private_balances, from, to);

        // Mint shares without revealing the recipient
        Token::at(context.this_address())
            .mint_shares_with_commitment_internal(commitment, assets, min_shares)
            .enqueue(&mut context);

        // Take the asset from the caller
        // Called after minting shares so that mint_shares_with_commitment_internal computes the amount of shares based on previous state.
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), assets, nonce)
            .call(&mut context);
    }

    /** ==========================================================
     * ==================== ISSUE ================================
     * ======================================================== */

    /// @notice Issues exactly the requested shares to a public balance and receives the underlying asset from a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param nonce The nonce used for authwitness
    #[public]
    fn issue_public_to_public(from: AztecAddress, to: AztecAddress, shares: u128, nonce: Field) {
        let total_assets = Token::at(storage.asset.read())
            .balance_of_public(context.this_address())
            .view(&mut context);
        let assets = convertToAssets(shares, total_assets, storage.total_supply.read());

        // transfer assets in
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), assets, nonce)
            .call(&mut context);

        // mint shares
        _increase_public_balance(storage.public_balances, to, shares);
        _increase_total_supply(storage.total_supply, shares);
    }

    /// @notice Issues exactly the requested shares to a private balance and receives the underlying asset from a public balance
    /// @dev The max_assets is calculated based on the ratio (total_supply + 1) / (total_assets + 1) plus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param nonce The nonce used for authwitness
    #[private]
    fn issue_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        nonce: Field,
    ) {
        // mint shares to the recipient in public
        _increase_private_balance(&mut context, storage.private_balances, from, to, shares);

        // Take the assets from the caller
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), max_assets, nonce)
            .enqueue(&mut context);

        // Validate the amount of assets transferred and send back any surplus
        Token::at(context.this_address())
            .validate_assets_transfer_internal(from, shares, max_assets)
            .enqueue(&mut context);

        // Increase shares total supply
        Token::at(context.this_address()).increase_total_supply_internal(shares).enqueue(
            &mut context,
        );
    }

    /// @notice Issues exactly the requested shares to a private balance and receives the underlying asset from a public balance
    /// @dev Any excess assets the caller has transferred in private, will be returned to the caller through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param nonce The nonce used for authwitness
    #[private]
    fn issue_private_to_public_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        nonce: Field,
    ) {
        // Transfer assets in
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), max_assets, nonce)
            .call(&mut context);

        // TODO: do we actually need to emit the partial note log, emitted inside uint_note::partial?
        let asset_commitment = Token::at(storage.asset.read())
            .initialize_transfer_commitment(from, from)
            .call(&mut context);

        // mint shares to the recipient in public
        Token::at(context.this_address())
            .validate_assets_transfer_with_commitment(asset_commitment, shares, max_assets)
            .enqueue(&mut context);

        Token::at(context.this_address()).increase_public_balance_internal(to, shares).enqueue(
            &mut context,
        );

        Token::at(context.this_address()).increase_total_supply_internal(shares).enqueue(
            &mut context,
        );
    }

    /// @notice Issues exactly the requested shares to a private balance and receives the underlying asset from a private balance
    /// @dev Any excess assets the caller has transferred in private, will be returned to the caller through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    ///      To optimize calls to this method, consider setting max_assets to an exact sum of notes, so that change is not returned twice (in private and later via commitment)
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param nonce The nonce used for authwitness
    #[private]
    fn issue_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        nonce: Field,
    ) {
        _increase_private_balance(&mut context, storage.private_balances, from, to, shares);

        // Transfer assets in
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), max_assets, nonce)
            .call(&mut context);

        // TODO: do we actually need to emit the partial note log, emitted inside uint_note::partial?
        let asset_commitment = Token::at(storage.asset.read())
            .initialize_transfer_commitment(from, from)
            .call(&mut context);

        // mint shares to the recipient in public
        Token::at(context.this_address())
            .validate_assets_transfer_with_commitment(asset_commitment, shares, max_assets)
            .enqueue(&mut context);

        Token::at(context.this_address()).increase_total_supply_internal(shares).enqueue(
            &mut context,
        );
    }

    /** ==========================================================
     * ==================== WITHDRAW =============================
     * ======================================================== */

    /** ==========================================================
     * ==================== REDEEM ===============================
     * ======================================================== */

    /// @notice Increases the public balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[public]
    #[internal]
    fn mint_shares_internal(to: AztecAddress, assets: u128) {
        let total_assets = Token::at(storage.asset.read())
            .balance_of_public(context.this_address())
            .view(&mut context);
        let shares = convertToShares(assets, total_assets, storage.total_supply.read());

        _increase_public_balance(storage.public_balances, to, shares);
        _increase_total_supply(storage.total_supply, shares);
    }

    /// @notice Increases shares total supply after privately minting `shares`
    /// @param assets The amount of underlying that will be sent to the contract
    /// @param shares The amount of requested shares
    #[public]
    #[internal]
    fn mint_private_shares_internal(assets: u128, shares: u128) {
        let total_assets = Token::at(storage.asset.read())
            .balance_of_public(context.this_address())
            .view(&mut context);
        let max_shares = convertToShares(assets, total_assets, storage.total_supply.read());

        assert(shares <= max_shares, "Too many shares requested");

        _increase_total_supply(storage.total_supply, shares);
    }

    /// @notice Increases the balance of the commitment by `amount`
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param amount The amount of tokens to increase the balance by
    #[public]
    #[internal]
    fn mint_shares_to_commitment_internal(commitment: PartialUintNote, assets: u128) {
        let total_assets = Token::at(storage.asset.read())
            .balance_of_public(context.this_address())
            .view(&mut context);
        let shares = convertToShares(assets, total_assets, storage.total_supply.read());
        _increase_commitment_balance(&mut context, commitment, shares);
        _increase_total_supply(storage.total_supply, shares);
    }

    /// @notice Increases the balance of the commitment by `amount`
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of tokens to increase the balance by
    /// @param min_shares The amount of tokens to increase the balance by
    #[public]
    #[internal]
    fn mint_shares_with_commitment_internal(
        commitment: PartialUintNote,
        assets: u128,
        min_shares: u128,
    ) {
        let total_assets = Token::at(storage.asset.read())
            .balance_of_public(context.this_address())
            .view(&mut context);
        let max_shares = convertToShares(assets, total_assets, storage.total_supply.read());

        let outstanding_shares = max_shares - min_shares; // Reverts with underflow if invalid
        if outstanding_shares > 0 {
            _increase_commitment_balance(&mut context, commitment, outstanding_shares);
        }

        _increase_total_supply(storage.total_supply, max_shares);
    }

    /// @notice Increases the balance of the commitment by `amount`
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of tokens to increase the balance by
    /// @param max_assets The maximum amount of assets to deposit. If the amount is greater then needed, the excess will be returned to the caller in private.
    #[public]
    #[internal]
    fn validate_assets_transfer_with_commitment(
        asset_commitment: PartialUintNote,
        shares: u128,
        max_assets: u128,
    ) {
        let total_assets = Token::at(storage.asset.read())
            .balance_of_public(context.this_address())
            .view(&mut context);
        let assets = convertToAssets(
            shares,
            total_assets - max_assets,
            storage.total_supply.read(),
        );

        let change = max_assets - assets; // Reverts with underflow if invalid
        if outstanding_shares > 0 {
            Token::at(storage.asset.read())
                .transfer_public_to_commitment(context.this_address(), change, asset_commitment, 0)
                .call(&mut context);
        }
    }

    /// @notice Increases the balance of the commitment by `amount`
    /// @param from The address of the sender
    /// @param shares The amount of tokens to increase the balance by
    /// @param max_assets The maximum amount of assets to deposit. If the amount is greater then needed, the excess will be returned to the caller in private.
    #[public]
    #[internal]
    fn validate_assets_transfer_internal(from: AztecAddress, shares: u128, max_assets: u128) {
        let total_assets = Token::at(storage.asset.read())
            .balance_of_public(context.this_address())
            .view(&mut context);
        let assets = convertToAssets(
            shares,
            total_assets - max_assets,
            storage.total_supply.read(),
        );
        assert(assets <= max_assets, "Insufficient assets transferred");

        let excess = max_assets - assets;
        Token::at(storage.asset.read())
            .transfer_public_to_public(context.this_address(), from, excess, 0)
            .call(&mut context);
    }

    #[contract_library_method]
    fn convertToShares(assets: u128, total_assets: u128, total_supply: u128) -> u128 {
        // TODO: handle overflow
        let shares = assets * (total_supply + offset()) / (total_assets + 1);
        shares
    }

    #[contract_library_method]
    fn convertToAssets(shares: u128, total_assets: u128, total_supply: u128) -> u128 {
        // TODO: handle overflow
        let assets = shares * (total_assets + 1) / (total_supply + offset());
        assets
    }

    #[contract_library_method]
    fn offset() -> u128 {
        // Power of 10.
        1
    }
}
