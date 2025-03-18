pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract Token {

    use aztec::{
        context::PrivateContext,
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
        note::{note_emission::OuterNoteEmission, note_interface::PartialNote},
        oracle::random::random,
        prelude::{AztecAddress, Map, PublicContext, PublicImmutable, PublicMutable},
        protocol_types::traits::{Hash, Serialize},
    };

    use authwit::auth::{
        assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
    };

    use uint_note::uint_note::UintNote;

    // compression library
    use compressed_string::FieldCompressedString;

    // encryption library
    use aztec::encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note;

    use balance_set::balance_set::BalanceSet;

    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    #[storage]
    struct Storage<Context> {
        // TODO: fix "is private and not visible from the current module" warning
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<U128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<U128, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
    }

    #[public]
    #[initializer]
    fn constructor_with_initial_supply(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        initial_supply: U128,
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
        amount: U128,
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
    fn transfer_private_to_public_with_hiding_point(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) -> Field {
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

        let hiding_point_slot =
            _prepare_transfer_public_to_private(&mut context, storage.private_balances, from, to);
        hiding_point_slot
    }

    #[private]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
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
    fn transfer_private_to_hiding_point(
        from: AztecAddress,
        amount: U128,
        hiding_point_slot: Field,
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

        Token::at(context.this_address())
            .increase_hiding_point_balance(hiding_point_slot, amount)
            .enqueue(&mut context);
    }

    #[private]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);

        Token::at(context.this_address()).decrease_public_balance(from, amount).enqueue(&mut context);

        _increase_private_balance(storage.private_balances, to, amount).emit(
            encode_and_encrypt_note(&mut context, to, from),
        );
    }

    #[private]
    fn prepare_transfer_public_to_private(from: AztecAddress, to: AztecAddress) -> Field {
        _prepare_transfer_public_to_private(&mut context, storage.private_balances, from, to)
    }

    #[internal]
    #[private]
    fn _recurse_subtract_balance(account: AztecAddress, amount: U128) -> U128 {
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
    fn transfer_public_to_public(from: AztecAddress, to: AztecAddress, amount: U128, nonce: Field) {
        _validate_from_public(&mut context, from, nonce);
        _decrease_public_balance(storage.public_balances, from, amount);
        _increase_public_balance(storage.public_balances, to, amount);
    }

    /// Finalizes a transfer of token `amount` from public balance of `from` to a private balance of `to`.
    /// The transfer must be prepared by calling `prepare_transfer_public_to_private` first and the resulting
    /// `hiding_point_slot` must be passed as an argument to this function.
    #[public]
    fn finalize_transfer_public_to_private(
        from: AztecAddress,
        amount: U128,
        hiding_point_slot: Field,
        nonce: Field,
    ) {
        _validate_from_public(&mut context, from, nonce);
        _finalize_transfer_public_to_private(
            &mut context,
            storage.public_balances,
            from,
            hiding_point_slot,
            amount,
        );
    }

    #[public]
    #[internal]
    fn store_payload_in_storage(slot: Field, point: [Field; 3], setup_log: [Field; 9]) {
        _store_payload_in_storage(&mut context, slot, point, setup_log);
    }

    #[public]
    #[internal]
    fn increase_public_balance(to: AztecAddress, amount: U128) {
        _increase_public_balance(storage.public_balances, to, amount);
    }

    #[public]
    #[internal]
    fn decrease_public_balance(from: AztecAddress, amount: U128) {
        _decrease_public_balance(storage.public_balances, from, amount);
    }

    #[public]
    #[internal]
    fn increase_hiding_point_balance(hiding_point_slot: Field, amount: U128) {
        _increase_hiding_point_balance(&mut context, hiding_point_slot, amount);
    }

    /** ==========================================================
    * ====================== VIEW FUNCTIONS =====================
    * ======================================================== */

    #[public]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> U128 {
        storage.public_balances.at(owner).read()
    }

    #[public]
    #[view]
    fn total_supply() -> U128 {
        storage.total_supply.read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    // TODO(#32): unconstrained fns cannot be injected in macros
    pub(crate) unconstrained fn balance_of_private(owner: AztecAddress) -> pub U128 {
        storage.private_balances.at(owner).balance_of()
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    #[private]
    fn mint_to_private(
        from: AztecAddress, // sender of the tag: TODO(#9887): this is not great?
        to: AztecAddress,
        amount: U128,
    ) {
        let minter = storage.minter.read();
        assert(minter.eq(context.msg_sender()), "caller is not minter");

        // We prepare the partial note to which we'll "send" the minted amount.
        let hiding_point_slot =
            _prepare_transfer_public_to_private(&mut context, storage.private_balances, minter, to);

        Token::at(context.this_address())
            ._finalize_mint_to_private_unsafe(amount, hiding_point_slot)
            .enqueue(&mut context);
    }

    #[public]
    fn mint_to_public(to: AztecAddress, amount: U128) {
        let minter = storage.minter.read();
        assert(minter.eq(context.msg_sender()), "caller is not minter");

        _increase_public_balance(storage.public_balances, to, amount);
        _increase_total_supply(storage.total_supply, amount);
    }

    #[public]
    fn finalize_mint_to_private(amount: U128, hiding_point_slot: Field) {
        let minter = storage.minter.read();
        assert(minter.eq(context.msg_sender()), "caller is not minter");

        _finalize_mint_to_private(
            &mut context,
            storage.total_supply,
            hiding_point_slot,
            amount,
        );
    }

    #[public]
    #[internal]
    fn _finalize_mint_to_private_unsafe(amount: U128, hiding_point_slot: Field) {
        _finalize_mint_to_private(
            &mut context,
            storage.total_supply,
            hiding_point_slot,
            amount,
        );
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    #[private]
    fn burn_private(from: AztecAddress, amount: U128, nonce: Field) {
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
    fn burn_public(from: AztecAddress, amount: U128, nonce: Field) {
        _validate_from_public(&mut context, from, nonce);
        _decrease_public_balance(storage.public_balances, from, amount);
        _decrease_total_supply(storage.total_supply, amount);
    }

    #[public]
    #[internal]
    fn decrease_total_supply(amount: U128) {
        _decrease_total_supply(storage.total_supply, amount);
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// Finalizes a public to private transfer
    #[contract_library_method]
    fn _finalize_transfer_public_to_private(
        context: &mut PublicContext,
        public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        hiding_point_slot: Field,
        amount: U128,
    ) {
        // Decreases the balance of the public balance of `from` by `amount`
        _decrease_public_balance(public_balances, from, amount);
        // Increases the balance of the hiding point
        _increase_hiding_point_balance(context, hiding_point_slot, amount);
    }

    /// Decreases the balance of the private balance of `account` by `amount`
    #[contract_library_method]
    fn _decrease_private_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: U128,
        max_notes: u32,
    ) -> OuterNoteEmission<UintNote> {
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
        amount: U128,
    ) -> OuterNoteEmission<UintNote> {
        // Increases `amount` of the private balance of `to`, and returns a note emission
        private_balances.at(to).add(to, amount)
    }

    #[contract_library_method]
    fn _increase_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
        to: AztecAddress,
        amount: U128,
    ) {
        // Read the current public balance of `to`, add `amount` to it,
        let new_balance = public_balances.at(to).read().add(amount);
        // write the result back to the storage
        public_balances.at(to).write(new_balance);
    }

    /// Updates the given storage pointer `public_balances` to decrease the balance of `from` by `amount`
    #[contract_library_method]
    fn _decrease_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        amount: U128,
    ) {
        // read the current public balance of `from`, subtract `amount`
        let new_balance = public_balances.at(from).read().sub(amount);
        // update the public balance of `from` with the new balance
        public_balances.at(from).write(new_balance);
    }

    // TODO: this will change when we upgrade to v81
    #[contract_library_method]
    fn _increase_hiding_point_balance(
        context: &mut PublicContext,
        hiding_point_slot: Field,
        amount: U128,
    ) {
        let finalization_payload =
            UintNote::finalization_payload().new(context, hiding_point_slot, amount);
        // NOTE: emitting here because expects UintNoteFinalizationPayload to exist.
        finalization_payload.emit();
    }

    #[contract_library_method]
    fn _subtract_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: U128,
        max_notes: u32,
    ) -> U128 {
        let subtracted = private_balances.at(account).try_sub(amount, max_notes);
        // Failing to subtract any amount means that the owner was unable to produce more notes that could be nullified.
        assert(subtracted > U128::zero(), "Balance too low");
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
        total_supply: PublicMutable<U128, &mut PublicContext>,
        hiding_point_slot: Field,
        amount: U128,
    ) {
        _increase_total_supply(total_supply, amount);
        _increase_hiding_point_balance(context, hiding_point_slot, amount);
    }

    // Increases the given storage pointer `total_supply` by `amount`
    #[contract_library_method]
    fn _increase_total_supply(total_supply: PublicMutable<U128, &mut PublicContext>, amount: U128) {
        let new_supply = total_supply.read().add(amount);
        total_supply.write(new_supply);
    }

    // Decreases the given storage pointer `total_supply` by `amount`
    #[contract_library_method]
    fn _decrease_total_supply(total_supply: PublicMutable<U128, &mut PublicContext>, amount: U128) {
        let new_supply = total_supply.read().sub(amount);
        total_supply.write(new_supply);
    }

    // TODO: this will change when we upgrade to v81
    #[contract_library_method]
    fn _store_payload_in_storage(
        context: &mut PublicContext,
        slot: Field,
        point: [Field; 3],
        setup_log: [Field; 9],
    ) {
        context.storage_write(slot, point);
        context.storage_write(slot + aztec::protocol_types::point::POINT_LENGTH as Field, setup_log);
    }

    #[contract_library_method]
    fn _prepare_transfer_public_to_private(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress, // sender of the tag: TODO(#9887): this is not great?
        to: AztecAddress,
    ) -> Field {
        let to_note_slot = private_balances.at(to).set.storage_slot;

        // We create a setup payload with unpopulated/zero `amount` for 'to'
        let note_randomness = unsafe { random() };
        let note_setup_payload = UintNote::setup_payload().new(to, note_randomness, to_note_slot);

        // We get the keys and encrypt the log of the note
        let setup_log = note_setup_payload.encrypt_log(context, to, from);

        let hiding_point_slot = note_setup_payload.hiding_point.x;

        // We don't need to perform a check that the value overwritten by `_store_point_in_transient_storage_unsafe`
        // is zero because the slot is the x-coordinate of the hiding point and hence we could only overwrite
        // the value in the slot with the same value. This makes usage of the `unsafe` method safe.

        let self = Token::at(context.this_address());
        self
            .store_payload_in_storage(
                hiding_point_slot,
                note_setup_payload.hiding_point.serialize(),
                setup_log,
            )
            .enqueue(context);

        hiding_point_slot
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
    fn _validate_from_public(context: &mut PublicContext, from: AztecAddress, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            // TODO(#34): uncomment assert_current_call_valid_authwit_public
            // assert_current_call_valid_authwit_public(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }
}
