pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract Token {
    // aztec library
    use aztec::{
        context::PrivateContext,
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
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
    use aztec::encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note;
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
        // TODO: fix "is private and not visible from the current module" warning
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<u128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
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

    /// @notice Transfer tokens from private to public balance
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

        Token::at(context.this_address()).increase_public_balance(to, amount).enqueue(&mut context);
    }

    /// @notice Transfer tokens from private to public balance with a commitment
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, enqueues a public call, and returns a partial note
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param nonce The nonce used for authwitness
    /// @return commitment The commitment (privacy entrance)
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

        Token::at(context.this_address()).increase_public_balance(to, amount).enqueue(&mut context);

        let commitment =
            _prepare_transfer_public_to_private(&mut context, storage.private_balances, from, to);
        commitment
    }

    /// @notice Transfer tokens from private to private balance
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

    /// @notice Transfer tokens from private to the recipient commitment (recipient must create a commitment first)
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
    /// @param from The address of the sender
    /// @param amount The amount of tokens to transfer
    /// @param commitment The commitment (privacy entrance that the recipient shares with the sender)
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

        Token::at(context.this_address()).increase_commitment_balance(commitment, amount).enqueue(
            &mut context,
        );
    }

    /// @notice Transfer tokens from public to private balance
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

        Token::at(context.this_address()).decrease_public_balance(from, amount).enqueue(&mut context);

        _increase_private_balance(&mut context, storage.private_balances, from, to, amount);
    }

    /// @notice Prepares a transfer from public to private balance
    /// @dev Returns a partial note that can be used to finalize the transfer
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @return commitment The partial note
    #[private]
    fn prepare_transfer_public_to_private(from: AztecAddress, to: AztecAddress) -> PartialUintNote {
        _prepare_transfer_public_to_private(&mut context, storage.private_balances, from, to)
    }

    /// @notice Recursively subtracts balance from private balance
    /// @dev Used to subtract balances that exceed the max notes limit
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @return The amount subtracted
    #[internal]
    #[private]
    fn recurse_subtract_balance(account: AztecAddress, amount: u128) -> u128 {
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

    /// @notice Transfers tokens from public to public balance
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

    /// @notice Finalizes a transfer of token `amount` from public balance of `from` to a private balance of `to`
    /// @dev The transfer must be prepared by calling `prepare_transfer_public_to_private` first and the resulting
    /// `commitment` must be passed as an argument to this function
    /// @param from The address of the sender
    /// @param amount The amount of tokens to transfer
    /// @param commitment The commitment (privacy entrance)
    /// @param nonce The nonce used for authwitness
    #[public]
    fn finalize_transfer_public_to_private(
        from: AztecAddress,
        amount: u128,
        commitment: PartialUintNote,
        nonce: Field,
    ) {
        _validate_from_public(&mut context, from, nonce);
        _finalize_transfer_public_to_private(
            &mut context,
            storage.public_balances,
            from,
            commitment,
            amount,
        );
    }

    /// @notice Stores a partial note in storage
    /// @dev Used to store the commitment (privacy entrance)
    /// @param slot The partial note to store
    #[public]
    #[internal]
    fn store_payload_in_storage(slot: PartialUintNote) {
        _store_payload_in_storage(&mut context, slot);
    }

    /// @notice Increases the balance of the public balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[public]
    #[internal]
    fn increase_public_balance(to: AztecAddress, amount: u128) {
        _increase_public_balance(storage.public_balances, to, amount);
    }

    /// @notice Decreases the balance of the public balance of `from` by `amount`
    /// @param from The address of the sender
    /// @param amount The amount of tokens to decrease the balance by
    #[public]
    #[internal]
    fn decrease_public_balance(from: AztecAddress, amount: u128) {
        _decrease_public_balance(storage.public_balances, from, amount);
    }

    /// @notice Increases the balance of the commitment by `amount`
    /// @param commitment The commitment (privacy entrance)
    /// @param amount The amount of tokens to increase the balance by
    #[public]
    #[internal]
    fn increase_commitment_balance(commitment: PartialUintNote, amount: u128) {
        _increase_commitment_balance(&mut context, commitment, amount);
    }

    /** ==========================================================
    * ====================== VIEW FUNCTIONS =====================
    * ======================================================== */

    /// @notice Returns the balance of the public balance of `owner`
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

    unconstrained fn balance_of_private(owner: AztecAddress) -> pub u128 {
        storage.private_balances.at(owner).balance_of()
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    /// @notice Mints tokens to a private balance
    /// @dev Mints tokens to a commitment and enqueues a public call to update the total supply
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[private]
    fn mint_to_private(
        from: AztecAddress, // sender of the tag: TODO(#9887): this is not great?
        to: AztecAddress,
        amount: u128,
    ) {
        let minter = storage.minter.read();
        _validate_minter(context.msg_sender(), minter);

        // We prepare the commitment to which we'll "send" the minted amount.
        let commitment =
            _prepare_transfer_public_to_private(&mut context, storage.private_balances, minter, to);

        Token::at(context.this_address())
            .finalize_mint_to_private_unsafe(amount, commitment)
            .enqueue(&mut context);
    }

    /// @notice Mints tokens to a public balance
    /// @dev Increases the balance of the public balance of `to` by `amount` and the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[public]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        _validate_minter(context.msg_sender(), storage.minter.read());

        _increase_public_balance(storage.public_balances, to, amount);
        _increase_total_supply(storage.total_supply, amount);
    }

    /// @notice Finalizes a mint to a private balance
    /// @dev Finalizes a mint to a commitment and updates the total supply
    /// @param amount The amount of tokens to mint
    /// @param commitment The commitment (privacy entrance)
    #[public]
    fn finalize_mint_to_private(amount: u128, commitment: PartialUintNote) {
        let minter = storage.minter.read();
        assert(minter.eq(context.msg_sender()), "caller is not minter");

        _finalize_mint_to_private(&mut context, storage.total_supply, commitment, amount);
    }

    #[public]
    #[internal]
    fn finalize_mint_to_private_unsafe(amount: u128, commitment: PartialUintNote) {
        _finalize_mint_to_private(&mut context, storage.total_supply, commitment, amount);
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns tokens from a private balance
    /// @dev Burns tokens from a private balance and enqueues a public call to update the total supply
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

        Token::at(context.this_address()).decrease_total_supply(amount).enqueue(&mut context);
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
    fn decrease_total_supply(amount: u128) {
        _decrease_total_supply(storage.total_supply, amount);
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// @notice Finalizes a public to private transfer
    /// @dev Decreases the balance of the public balance of `from` by `amount` and increases the balance of the commitment
    /// @param context The context of the public call
    /// @param public_balances The storage pointer to the public balances
    /// @param from The address of the sender
    /// @param commitment The commitment (privacy entrance)
    /// @param amount The amount of tokens to transfer
    #[contract_library_method]
    fn _finalize_transfer_public_to_private(
        context: &mut PublicContext,
        public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        commitment: PartialUintNote,
        amount: u128,
    ) {
        // Decreases the balance of the public balance of `from` by `amount`
        _decrease_public_balance(public_balances, from, amount);
        // Increases the balance of the commitment
        _increase_commitment_balance(context, commitment, amount);
    }

    /// Validates that the caller is the minter
    #[contract_library_method]
    fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }

    /// Decreases the private balance of `account` by `amount` and emits a private balance note to account
    #[contract_library_method]
    fn _decrease_private_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: u128,
        max_notes: u32,
    ) {
        // Subtracts `amount` of the private balance of `account`
        let change = _subtract_balance(context, private_balances, account, amount, max_notes);
        // Increases `change` of the private balance of `account`, and emits a private balance note to account
        private_balances.at(account).add(account, change).emit(encode_and_encrypt_note(
            context,
            account,
            account,
        ));
    }

    /// @notice Updates the given storage pointer `private_balances` to increase the balance of `to` by `amount`
    /// @param private_balances The storage pointer to the private balances
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    /// @return The note emission
    #[contract_library_method]
    fn _increase_private_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
    ) {
        // Increases `amount` of the private balance of `to`, and emits a private balance note to `to` from `from`
        private_balances.at(to).add(to, amount).emit(encode_and_encrypt_note(context, to, from));
    }

    /// @notice Updates the given storage pointer `public_balances` to increase the balance of `to` by `amount`
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

    /// @notice Updates the given storage pointer `public_balances` to decrease the balance of `from` by `amount`
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

    // TODO: this will change when we upgrade to v81
    /// @notice Completes a partial note
    /// @dev Completes a partial note and increases the balance of the commitment by `amount`
    /// @param context The context of the public call
    /// @param commitment The commitment (privacy entrance)
    /// @param amount The amount of tokens to increase the balance of the commitment by
    #[contract_library_method]
    fn _increase_commitment_balance(
        context: &mut PublicContext,
        commitment: PartialUintNote,
        amount: u128,
    ) {
        commitment.complete(amount, context);
    }

    /// @notice Subtracts balance from private balance
    /// @dev Subtracts amount from private balance and returns the change to the owner, recursively if necessary
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

            Token::at(context.this_address()).recurse_subtract_balance(account, remaining).call(
                context,
            )
        }
    }

    /// @notice Finalizes a mint to a private balance
    /// @dev Increases the total supply and the balance of the commitment by `amount`
    /// @param context The context of the public call
    /// @param total_supply The storage pointer to the total supply
    /// @param commitment The commitment (privacy entrance)
    /// @param amount The amount of tokens to mint
    #[contract_library_method]
    fn _finalize_mint_to_private(
        context: &mut PublicContext,
        total_supply: PublicMutable<u128, &mut PublicContext>,
        commitment: PartialUintNote,
        amount: u128,
    ) {
        _increase_total_supply(total_supply, amount);
        _increase_commitment_balance(context, commitment, amount);
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

    // TODO: this will change when we upgrade to v81
    /// @notice Stores a partial note in storage
    /// @param context The context of the public call
    /// @param commitment The partial note to store
    #[contract_library_method]
    fn _store_payload_in_storage(context: &mut PublicContext, commitment: PartialUintNote) {
        context.storage_write(commitment.commitment(), true);
    }

    /// @notice Prepares a transfer from public to private balance
    /// @param context The context of the private call
    /// @param private_balances The storage pointer to the private balances
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @return The partial note that can be used to finalize the transfer
    #[contract_library_method]
    fn _prepare_transfer_public_to_private(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress, // sender of the tag: TODO(#9887): this is not great?
        to: AztecAddress,
    ) -> PartialUintNote {
        let commitment = UintNote::partial(
            to,
            private_balances.at(to).set.storage_slot,
            context,
            to,
            from,
        );

        commitment
    }

    /** ==========================================================
     * ================== AUTH LIBRARIES =========================
     * ======================================================== */

    /// @notice Validates that the caller is the owner of the private balance
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

    /// @notice Validates that the caller is the owner of the public balance
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
}
