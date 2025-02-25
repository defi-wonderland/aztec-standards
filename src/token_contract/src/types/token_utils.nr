pub comptime fn token(m: Module) -> Quoted {
    let token_body = quote {

        global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
        global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;
        
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
            TokenLib::_validate_from_private(from, nonce, &mut context);

            TokenLib::_subtract_exact_balance(
                &mut context,
                storage.private_balances,
                from,
                amount,
                INITIAL_TRANSFER_CALL_MAX_NOTES,
            )
                .emit(encode_and_encrypt_note(&mut context, from, from));

            // let self = Token::at(context.this_address());
            // self.increase_public_balance(to, amount).enqueue(&mut context);
        }

        #[private]
        fn transfer_private_to_private(
            from: AztecAddress,
            to: AztecAddress,
            amount: U128,
            nonce: Field,
        ) {
            TokenLib::_validate_from_private(from, nonce, &mut context);

            TokenLib::_subtract_exact_balance(
                &mut context,
                storage.private_balances,
                from,
                amount,
                INITIAL_TRANSFER_CALL_MAX_NOTES,
            )
                .emit(encode_and_encrypt_note(&mut context, from, from));

            TokenLib::_increase_private_balance(storage.private_balances, to, amount).emit(
                encode_and_encrypt_note(&mut context, to, from),
            );
        }

        // Transfers token `amount` from public balance of message sender to a private balance of `to`.
        #[private]
        fn transfer_public_to_private(
            from: AztecAddress,
            to: AztecAddress,
            amount: U128,
            nonce: Field,
        ) {
            TokenLib::_validate_from_private(from, nonce, &mut context);

            // let self = Token::at(context.this_address());
            // self.decrease_public_balance(from, amount).enqueue(&mut context);

            TokenLib::_increase_private_balance(storage.private_balances, to, amount).emit(
                encode_and_encrypt_note(&mut context, to, from),
            );
        }

        #[private]
        fn prepare_transfer_public_to_private(to: AztecAddress, from: AztecAddress) -> Field {
            TokenLib::_prepare_transfer_public_to_private(
                from,
                to,
                &mut context,
                storage.private_balances,
            )
        }

        #[internal]
        #[private]
        fn _recurse_subtract_balance(account: AztecAddress, amount: U128) -> U128 {
            TokenLib::_subtract_balance(
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
            if (!from.eq(context.msg_sender())) {
                assert_current_call_valid_authwit_public(&mut context, from);
            } else {
                assert(nonce == 0, "invalid nonce");
            }
            TokenLib::_decrease_public_balance(storage.public_balances, from, amount);
            TokenLib::_increase_public_balance(storage.public_balances, to, amount);
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
            if (!from.eq(context.msg_sender())) {
                assert_current_call_valid_authwit_public(&mut context, from);
            } else {
                assert(nonce == 0, "invalid nonce");
            }
            TokenLib::_finalize_transfer_public_to_private(
                from,
                amount,
                hiding_point_slot,
                &mut context,
                storage.public_balances,
            );
        }

        #[public]
        #[internal]
        fn store_payload_in_storage(slot: Field, point: Point, setup_log: [Field; 9]) {
            context.storage_write(slot, point);
            context.storage_write(slot + aztec::protocol_types::point::POINT_LENGTH as Field, setup_log);
        }

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
    };

    quote {
        $token_body
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

    pub fn _prepare_transfer_public_to_private(
        from: AztecAddress, // sender of the tag: TODO(#9887): this is not great?
        to: AztecAddress,
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
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
}
