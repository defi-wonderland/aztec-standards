pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract Token {

    use aztec::{
        context::PrivateContext,
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
        prelude::{AztecAddress, Map, PublicContext, PublicImmutable, PublicMutable},
    };

    use authwit::auth::{
        assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
    };

    use uint_note::uint_note::{PartialUintNote, UintNote};
    // compression library
    use compressed_string::FieldCompressedString;

    // encryption library
    use aztec::encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note;

    use balance_set::balance_set::BalanceSet;

    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<u128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
    }

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

    #[private]
    fn initialize_transfer_commitment(from: AztecAddress, to: AztecAddress) -> PartialUintNote {
        _initialize_transfer_commitment(&mut context, storage.private_balances, from, to)
    }

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

    #[public]
    fn transfer_public_to_public(from: AztecAddress, to: AztecAddress, amount: u128, nonce: Field) {
        _validate_from_public(&mut context, from, nonce);

        _decrease_public_balance(storage.public_balances, from, amount);
        _increase_public_balance(storage.public_balances, to, amount);
    }

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

    #[public]
    #[internal]
    fn store_commitment_in_storage_internal(slot: PartialUintNote) {
        _store_commitment_in_storage(&mut context, slot);
    }

    #[public]
    #[internal]
    fn increase_public_balance_internal(to: AztecAddress, amount: u128) {
        _increase_public_balance(storage.public_balances, to, amount);
    }

    #[public]
    #[internal]
    fn decrease_public_balance_internal(from: AztecAddress, amount: u128) {
        _decrease_public_balance(storage.public_balances, from, amount);
    }

    #[public]
    #[internal]
    fn increase_commitment_balance_internal(commitment: PartialUintNote, amount: u128) {
        _increase_commitment_balance(&mut context, commitment, amount);
    }

    /** ==========================================================
    * ====================== VIEW FUNCTIONS =====================
    * ======================================================== */

    #[public]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> u128 {
        storage.public_balances.at(owner).read()
    }

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

    #[private]
    fn mint_to_private(from: AztecAddress, to: AztecAddress, amount: u128) {
        _validate_minter(context.msg_sender(), storage.minter.read());

        // We prepare the commitment to which we'll "send" the minted amount.
        let commitment =
            _initialize_transfer_commitment(&mut context, storage.private_balances, from, to);

        Token::at(context.this_address()).mint_to_commitment_internal(amount, commitment).enqueue(
            &mut context,
        );
    }

    #[public]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        _validate_minter(context.msg_sender(), storage.minter.read());

        _increase_public_balance(storage.public_balances, to, amount);
        _increase_total_supply(storage.total_supply, amount);
    }

    #[public]
    fn mint_to_commitment(amount: u128, commitment: PartialUintNote) {
        _validate_minter(context.msg_sender(), storage.minter.read());

        _increase_total_supply(storage.total_supply, amount);
        _increase_commitment_balance(&mut context, commitment, amount);
    }

    #[public]
    #[internal]
    fn mint_to_commitment_internal(amount: u128, commitment: PartialUintNote) {
        _increase_total_supply(storage.total_supply, amount);
        _increase_commitment_balance(&mut context, commitment, amount);
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

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

    #[public]
    fn burn_public(from: AztecAddress, amount: u128, nonce: Field) {
        _validate_from_public(&mut context, from, nonce);

        _decrease_public_balance(storage.public_balances, from, amount);
        _decrease_total_supply(storage.total_supply, amount);
    }

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

    /// Increases the private balance of `to` by `amount` and emits a private balance note to `to` from `from`
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

    /// Updates the given storage pointer `public_balances` to decrease the balance of `from` by `amount`
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

    #[contract_library_method]
    fn _increase_commitment_balance(
        context: &mut PublicContext,
        commitment: PartialUintNote,
        amount: u128,
    ) {
        commitment.complete(amount, context);
    }

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

    // Increases the given storage pointer `total_supply` by `amount`
    #[contract_library_method]
    fn _increase_total_supply(total_supply: PublicMutable<u128, &mut PublicContext>, amount: u128) {
        let new_supply = total_supply.read() + amount;
        total_supply.write(new_supply);
    }

    // Decreases the given storage pointer `total_supply` by `amount`
    #[contract_library_method]
    fn _decrease_total_supply(total_supply: PublicMutable<u128, &mut PublicContext>, amount: u128) {
        let new_supply = total_supply.read() - amount;
        total_supply.write(new_supply);
    }

    #[contract_library_method]
    fn _store_commitment_in_storage(context: &mut PublicContext, commitment: PartialUintNote) {
        context.storage_write(commitment.commitment(), true);
    }

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

        commitment
    }

    /** ==========================================================
     * ================== AUTH LIBRARIES =========================
     * ======================================================== */

    #[contract_library_method]
    fn _validate_from_private(context: &mut PrivateContext, from: AztecAddress, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }

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
