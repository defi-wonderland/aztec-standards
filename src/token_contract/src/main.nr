pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract Token {

    use aztec::{
        context::PrivateContext,
        encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note,
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
        note::{note_emission::OuterNoteEmission, note_interface::PartialNote},
        oracle::random::random,
        prelude::{AztecAddress, Map, PublicContext, PublicImmutable, PublicMutable},
        protocol_types::traits::{Deserialize, Hash, Packable, Serialize},
    };

    use authwit::auth::{
        assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
    };

    // compression library
    use compressed_string::FieldCompressedString;

    use balance_set::balance_set::BalanceSet;
    use bignum_field::{
        bignum_field::BigNumField,
        bignum_field_note::{BigNumFieldNote, PartialBigNumFieldNote},
    };

    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    #[storage]
    struct Storage<Context> {
        // TODO: fix "is private and not visible from the current module" warning
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<BigNumField, Context>,
        public_balances: Map<AztecAddress, PublicMutable<BigNumField, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
    }

    #[public]
    #[initializer]
    fn constructor_with_initial_supply(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        initial_supply: BigNumField,
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
        amount: BigNumField,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        )
            .emit(encode_and_encrypt_note(&mut context, from, from));

        Token::at(context.this_address()).increase_public_balance(to, amount).enqueue(&mut context);
    }

    #[private]
    fn transfer_private_to_public_with_commitment(
        from: AztecAddress,
        to: AztecAddress,
        amount: BigNumField,
        nonce: Field,
    ) -> PartialBigNumFieldNote {
        _validate_from_private(&mut context, from, nonce);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        )
            .emit(encode_and_encrypt_note(&mut context, from, from));

        Token::at(context.this_address()).increase_public_balance(to, amount).enqueue(&mut context);

        let commitment =
            _prepare_transfer_public_to_private(&mut context, storage.private_balances, from, to);
        commitment
    }

    #[private]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: BigNumField,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        )
            .emit(encode_and_encrypt_note(&mut context, from, from));

        _increase_private_balance(storage.private_balances, to, amount).emit(
            encode_and_encrypt_note(&mut context, to, from),
        );
    }

    #[private]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        amount: BigNumField,
        commitment: PartialBigNumFieldNote,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        )
            .emit(encode_and_encrypt_note(&mut context, from, from));

        Token::at(context.this_address()).increase_commitment_balance(commitment, amount).enqueue(
            &mut context,
        );
    }

    #[private]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: BigNumField,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);

        Token::at(context.this_address()).decrease_public_balance(from, amount).enqueue(&mut context);

        _increase_private_balance(storage.private_balances, to, amount).emit(
            encode_and_encrypt_note(&mut context, to, from),
        );
    }

    #[private]
    fn prepare_transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
    ) -> PartialBigNumFieldNote {
        _prepare_transfer_public_to_private(&mut context, storage.private_balances, from, to)
    }

    #[internal]
    #[private]
    fn _recurse_subtract_balance(account: AztecAddress, amount: BigNumField) -> BigNumField {
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
    fn transfer_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: BigNumField,
        nonce: Field,
    ) {
        _validate_from_public(&mut context, from, nonce);
        _decrease_public_balance(storage.public_balances, from, amount);
        _increase_public_balance(storage.public_balances, to, amount);
    }

    /// Finalizes a transfer of token `amount` from public balance of `from` to a private balance of `to`.
    /// The transfer must be prepared by calling `prepare_transfer_public_to_private` first and the resulting
    /// `commitment` must be passed as an argument to this function.
    #[public]
    fn finalize_transfer_public_to_private(
        from: AztecAddress,
        amount: BigNumField,
        commitment: PartialBigNumFieldNote,
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

    #[public]
    #[internal]
    fn store_payload_in_storage(slot: PartialBigNumFieldNote) {
        _store_payload_in_storage(&mut context, slot);
    }

    #[public]
    #[internal]
    fn increase_public_balance(to: AztecAddress, amount: BigNumField) {
        _increase_public_balance(storage.public_balances, to, amount);
    }

    #[public]
    #[internal]
    fn decrease_public_balance(from: AztecAddress, amount: BigNumField) {
        _decrease_public_balance(storage.public_balances, from, amount);
    }

    #[public]
    #[internal]
    fn increase_commitment_balance(commitment: PartialBigNumFieldNote, amount: BigNumField) {
        _increase_commitment_balance(&mut context, commitment, amount);
    }

    /** ==========================================================
    * ====================== VIEW FUNCTIONS =====================
    * ======================================================== */

    #[public]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> BigNumField {
        storage.public_balances.at(owner).read()
    }

    #[public]
    #[view]
    fn total_supply() -> BigNumField {
        storage.total_supply.read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    unconstrained fn balance_of_private(owner: AztecAddress) -> pub BigNumField {
        storage.private_balances.at(owner).balance_of()
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    #[private]
    fn mint_to_private(
        from: AztecAddress, // sender of the tag: TODO(#9887): this is not great?
        to: AztecAddress,
        amount: BigNumField,
    ) {
        let minter = storage.minter.read();
        assert(minter.eq(context.msg_sender()), "caller is not minter");

        // We prepare the commitment to which we'll "send" the minted amount.
        let commitment =
            _prepare_transfer_public_to_private(&mut context, storage.private_balances, minter, to);

        Token::at(context.this_address())
            ._finalize_mint_to_private_unsafe(amount, commitment)
            .enqueue(&mut context);
    }

    #[public]
    fn mint_to_public(to: AztecAddress, amount: BigNumField) {
        let minter = storage.minter.read();
        assert(minter.eq(context.msg_sender()), "caller is not minter");

        _increase_public_balance(storage.public_balances, to, amount);
        _increase_total_supply(storage.total_supply, amount);
    }

    #[public]
    fn finalize_mint_to_private(amount: BigNumField, commitment: PartialBigNumFieldNote) {
        let minter = storage.minter.read();
        assert(minter.eq(context.msg_sender()), "caller is not minter");

        _finalize_mint_to_private(&mut context, storage.total_supply, commitment, amount);
    }

    #[public]
    #[internal]
    fn _finalize_mint_to_private_unsafe(amount: BigNumField, commitment: PartialBigNumFieldNote) {
        _finalize_mint_to_private(&mut context, storage.total_supply, commitment, amount);
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    #[private]
    fn burn_private(from: AztecAddress, amount: BigNumField, nonce: Field) {
        _validate_from_private(&mut context, from, nonce);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        )
            .emit(encode_and_encrypt_note(&mut context, from, from));

        Token::at(context.this_address()).decrease_total_supply(amount).enqueue(&mut context);
    }

    #[public]
    fn burn_public(from: AztecAddress, amount: BigNumField, nonce: Field) {
        _validate_from_public(&mut context, from, nonce);
        _decrease_public_balance(storage.public_balances, from, amount);
        _decrease_total_supply(storage.total_supply, amount);
    }

    #[public]
    #[internal]
    fn decrease_total_supply(amount: BigNumField) {
        _decrease_total_supply(storage.total_supply, amount);
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// Finalizes a public to private transfer
    #[contract_library_method]
    fn _finalize_transfer_public_to_private(
        context: &mut PublicContext,
        public_balances: Map<AztecAddress, PublicMutable<BigNumField, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        commitment: PartialBigNumFieldNote,
        amount: BigNumField,
    ) {
        // Decreases the balance of the public balance of `from` by `amount`
        _decrease_public_balance(public_balances, from, amount);
        // Increases the balance of the commitment
        _increase_commitment_balance(context, commitment, amount);
    }

    /// Decreases the balance of the private balance of `account` by `amount`
    #[contract_library_method]
    fn _decrease_private_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: BigNumField,
        max_notes: u32,
    ) -> OuterNoteEmission<BigNumFieldNote> {
        // Subtracts `amount` of the private balance of `account`
        let change = _subtract_balance(context, private_balances, account, amount, max_notes);
        // Increases the balance of the private balance of `account` by `change`
        _increase_private_balance(private_balances, account, change)
    }

    /// Increases the balance of the private balance of `to` by `amount`
    #[contract_library_method]
    fn _increase_private_balance(
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        to: AztecAddress, // todo: rename to `account`?
        amount: BigNumField,
    ) -> OuterNoteEmission<BigNumFieldNote> {
        // Increases `amount` of the private balance of `to`, and returns a note emission
        private_balances.at(to).add(to, amount)
    }

    #[contract_library_method]
    fn _increase_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<BigNumField, &mut PublicContext>, &mut PublicContext>,
        to: AztecAddress,
        amount: BigNumField,
    ) {
        // Read the current public balance of `to`, add `amount` to it,
        let new_balance = public_balances.at(to).read() + amount;
        // write the result back to the storage
        public_balances.at(to).write(new_balance);
    }

    /// Updates the given storage pointer `public_balances` to decrease the balance of `from` by `amount`
    #[contract_library_method]
    fn _decrease_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<BigNumField, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        amount: BigNumField,
    ) {
        // read the current public balance of `from`, subtract `amount`
        let new_balance = public_balances.at(from).read() - amount;
        // update the public balance of `from` with the new balance
        public_balances.at(from).write(new_balance);
    }

    #[contract_library_method]
    fn _increase_commitment_balance(
        context: &mut PublicContext,
        commitment: PartialBigNumFieldNote,
        amount: BigNumField,
    ) {
        commitment.complete(amount, context);
    }

    #[contract_library_method]
    fn _subtract_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: BigNumField,
        max_notes: u32,
    ) -> BigNumField {
        let subtracted = private_balances.at(account).try_sub(amount, max_notes);
        // Failing to subtract any amount means that the owner was unable to produce more notes that could be nullified.
        assert(subtracted > BigNumField::zero(), "Balance too low");
        if subtracted >= amount {
            // We have achieved our goal of nullifying notes that add up to more than amount, so we return the change.
            subtracted - amount
        } else {
            // try_sub failed to nullify enough notes to reach the target amount, so we compute the amount remaining
            // and try again.
            let remaining = amount - subtracted;

            let self = Token::at(context.this_address());
            self._recurse_subtract_balance(account, remaining).call(context)
        }
    }

    #[contract_library_method]
    fn _finalize_mint_to_private(
        context: &mut PublicContext,
        total_supply: PublicMutable<BigNumField, &mut PublicContext>,
        commitment: PartialBigNumFieldNote,
        amount: BigNumField,
    ) {
        _increase_total_supply(total_supply, amount);
        _increase_commitment_balance(context, commitment, amount);
    }

    // Increases the given storage pointer `total_supply` by `amount`
    #[contract_library_method]
    fn _increase_total_supply(
        total_supply: PublicMutable<BigNumField, &mut PublicContext>,
        amount: BigNumField,
    ) {
        let new_supply = total_supply.read() + amount;
        total_supply.write(new_supply);
    }

    // Decreases the given storage pointer `total_supply` by `amount`
    #[contract_library_method]
    fn _decrease_total_supply(
        total_supply: PublicMutable<BigNumField, &mut PublicContext>,
        amount: BigNumField,
    ) {
        let new_supply = total_supply.read() - amount;
        total_supply.write(new_supply);
    }

    // TODO: this will change when we upgrade to v81
    #[contract_library_method]
    fn _store_payload_in_storage(context: &mut PublicContext, commitment: PartialBigNumFieldNote) {
        context.storage_write(commitment.commitment(), true);
    }

    #[contract_library_method]
    fn _prepare_transfer_public_to_private(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress, // sender of the tag: TODO(#9887): this is not great?
        to: AztecAddress,
    ) -> PartialBigNumFieldNote {
        let commitment = BigNumFieldNote::partial(
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
