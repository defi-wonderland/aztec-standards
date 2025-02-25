pub comptime fn token_utils(m: Module) -> Quoted {
    let methods = quote {
        #[public]
        #[internal]
        fn increase_public_balance(to: AztecAddress, amount: U128) {
            TokenLib::_increase_public_balance(storage.public_balances, to, amount);
        }

        #[public]
        #[internal]
        fn decrease_public_balance(from: AztecAddress, amount: U128) {
            TokenLib::_decrease_public_balance(storage.public_balances, from, amount);
        }
    };

    quote {
        $methods
    }
}

pub mod TokenLib {
    use dep::aztec::{
        context::PrivateContext,
        note::{note_emission::OuterNoteEmission, note_interface::PartialNote},
        oracle::random::random,
        prelude::{AztecAddress, Map, PublicContext, PublicMutable},
        protocol_types::abis::function_selector::FunctionSelector,
    };

    use dep::uint_note::uint_note::UintNote;

    use dep::authwit::auth::assert_current_call_valid_authwit;

    use crate::types::balance_set::BalanceSet;

    /** ==========================================================
     * ======================= LIBRARIES =========================
     * ======================================================== */

    pub fn _validate_from_private(from: AztecAddress, nonce: Field, context: &mut PrivateContext) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }

    pub fn _finalize_transfer_public_to_private(
        from: AztecAddress,
        amount: U128,
        hiding_point_slot: Field,
        context: &mut PublicContext,
        public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
    ) {
        _decrease_public_balance(public_balances, from, amount);
        _increase_hiding_point_balance(context, hiding_point_slot, amount);
    }

    pub fn _subtract_exact_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: U128,
        max_notes: u32,
    ) -> OuterNoteEmission<UintNote> {
        // We reduce `from`'s balance by amount by recursively removing notes over potentially multiple calls. This
        // method keeps the gate count for each individual call low - reading too many notes at once could result in
        // circuits in which proving is not feasible.
        // Since the sum of the amounts in the notes we nullified was potentially larger than amount, we create a new
        // note for `from` with the change amount, e.g. if `amount` is 10 and two notes are nullified with amounts 8 and
        // 5, then the change will be 3 (since 8 + 5 - 10 = 3).
        let change = _subtract_balance(context, private_balances, account, amount, max_notes);

        _increase_private_balance(private_balances, account, change)
    }

    pub fn _increase_private_balance(
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        to: AztecAddress,
        amount: U128,
    ) -> OuterNoteEmission<UintNote> {
        private_balances.at(to).add(to, amount)
    }

    pub fn _increase_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
        to: AztecAddress,
        amount: U128,
    ) {
        let new_balance = public_balances.at(to).read().add(amount);
        public_balances.at(to).write(new_balance);
    }

    pub fn _decrease_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        amount: U128,
    ) {
        let new_balance = public_balances.at(from).read().sub(amount);
        public_balances.at(from).write(new_balance);
    }

    pub fn _increase_hiding_point_balance(
        context: &mut PublicContext,
        hiding_point_slot: Field,
        amount: U128,
    ) {
        let finalization_payload =
            UintNote::finalization_payload().new(context, hiding_point_slot, amount);
        // NOTE: emitting here because expects UintNoteFinalizationPayload to exist.
        finalization_payload.emit();
    }

    pub fn _subtract_balance(
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

            // NOTE: hacky way to call itself before Token is compiled to be used as a library.
            // let self = Token::at(context.this_address());
            // self._recurse_subtract_balance(account, remaining).call(context)

            let result: Field = context
                .call_private_function(
                    context.this_address(),
                    FunctionSelector::from_signature(
                        "_recurse_subtract_balance((Field),(Field,Field))",
                    ),
                    [account.to_field(), remaining.to_field()],
                )
                .get_preimage();

            U128::from_integer(result)
        }
    }

    /// This function exists separately from `prepare_transfer_public_to_private` solely as an optimization as it allows
    /// us to have it inlined in the `transfer_public_to_private` function which results in one less kernel iteration.
    ///
    /// TODO(#9180): Consider adding macro support for functions callable both as an entrypoint and as an internal
    /// function.
    pub fn _prepare_transfer_public_to_private(
        from: AztecAddress, // sender of the tag: TODO(#9887): this is not great?
        to: AztecAddress,
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
    ) -> Field {
        let to_note_slot = private_balances.at(to).set.storage_slot;

        // We create a setup payload with unpopulated/zero `amount` for 'to'
        // TODO(#7775): Manually fetching the randomness here is not great. If we decide to include randomness in all
        // notes we could just inject it in macros.

        // Safety: We use the randomness to preserve the privacy of the note recipient by preventing brute-forcing,
        // so a malicious sender could use non-random values to make the note less private. But they already know
        // the full note pre-image anyway, and so the recipient already trusts them to not disclose this
        // information. We can therefore assume that the sender will cooperate in the random value generation.
        let note_randomness = unsafe { random() };
        let note_setup_payload = UintNote::setup_payload().new(to, note_randomness, to_note_slot);

        // We get the keys and encrypt the log of the note
        let setup_log = note_setup_payload.encrypt_log(context, to, from);

        // Using the x-coordinate as a hiding point slot is safe against someone else interfering with it because
        // we have a guarantee that the public functions of the transaction are executed right after the private ones
        // and for this reason the protocol guarantees that nobody can front-run us in consuming the hiding point.
        // This guarantee would break if `finalize_transfer_public_to_private` was not called in the same transaction. This
        // however is not the flow we are currently concerned with. To support the multi-transaction flow we could
        // introduce a `from` function argument, hash the x-coordinate with it and then repeat the hashing in
        // `finalize_transfer_public_to_private`.
        //
        // We can also be sure that the `hiding_point_slot` will not overwrite any other value in the storage because
        // in our state variables we derive slots using a different hash function from multi scalar multiplication
        // (MSM).
        let hiding_point_slot = note_setup_payload.hiding_point.x;

        // We don't need to perform a check that the value overwritten by `_store_point_in_transient_storage_unsafe`
        // is zero because the slot is the x-coordinate of the hiding point and hence we could only overwrite
        // the value in the slot with the same value. This makes usage of the `unsafe` method safe.

        // let self = Token::at(context.this_address());
        // self
        //     .store_payload_in_storage(hiding_point_slot, note_setup_payload.hiding_point, setup_log)
        //     .enqueue(context);

        // context.call_public_function(
        //     context.this_address(),
        //     FunctionSelector::from_signature("store_payload_in_storage((Field),(Point),(CompressedString))"),
        //     [hiding_point_slot, note_setup_payload.hiding_point, setup_log],
        // ).enqueue(context);

        hiding_point_slot
    }

    #[contract_library_method]
    fn _finalize_mint_to_private(
        amount: U128,
        hiding_point_slot: Field,
        context: &mut PublicContext,
        total_supply: PublicMutable<U128, &mut PublicContext>,
    ) {
        // First we increase the total supply by the `amount`
        let supply = total_supply.read().add(amount);
        total_supply.write(supply);

        _increase_hiding_point_balance(context, hiding_point_slot, amount);
    }
}
