mod transferrable;
mod mintable;

pub comptime fn token(m: Module) -> Quoted {
    let token_body = transferrable::TRANSFERRABLE_CODE;
    let mintable_body = mintable::MINTABLE_CODE;

    quote {
        $token_body
        $mintable_body
    }
}

pub mod TokenLib {
    use aztec::{
        context::PrivateContext,
        note::{note_emission::OuterNoteEmission, note_interface::PartialNote},
        oracle::random::random,
        prelude::{AztecAddress, Map, Point, PublicContext, PublicMutable},
        protocol_types::abis::function_selector::FunctionSelector,
    };

    use crate::types::balance_set::BalanceSet;
    use uint_note::uint_note::UintNote;

    /** ==========================================================
     * ======================= LIBRARIES =========================
     * ======================================================== */

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

    pub fn _decrease_private_balance(
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

    pub fn _private_increase_public_balance(
        context: &mut PrivateContext,
        to: AztecAddress,
        amount: U128,
    ) {
        // let self = Token::at(context.this_address());
        // self.increase_public_balance(to, amount).enqueue(&mut context);
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("increase_public_balance((Field),(Field,Field))"),
            [to.to_field(), amount.to_field()],
        );
    }

    pub fn _private_decrease_public_balance(
        context: &mut PrivateContext,
        from: AztecAddress,
        amount: U128,
    ) {
        // let self = Token::at(context.this_address());
        // self.decrease_public_balance(from, amount).enqueue(&mut context);
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("decrease_public_balance((Field),(Field,Field))"),
            [from.to_field(), amount.to_field()],
        );
    }

    pub fn _finalize_mint_to_private(
        amount: U128,
        hiding_point_slot: Field,
        context: &mut PublicContext,
        total_supply: PublicMutable<U128, &mut PublicContext>,
    ) {
        let new_supply = total_supply.read().add(amount);
        total_supply.write(new_supply);
        _increase_hiding_point_balance(context, hiding_point_slot, amount);
    }

    pub fn _private_finalize_mint_to_private(
        context: &mut PrivateContext,
        amount: U128,
        hiding_point_slot: Field,
    ) {
        // let self: Token = Token::at(context.this_address());
        // self
        //     ._finalize_mint_to_private_unsafe(context.msg_sender(), amount, hiding_point_slot)
        //     .enqueue(&mut context);

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("finalize_mint_to_private((Field,Field),Field)"),
            [amount.to_field(), hiding_point_slot.to_field()],
        );
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

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature(
                "store_payload_in_storage(Field,(Field,Field,Field),(Field,Field,Field,Field,Field,Field,Field,Field,Field))",
            ),
            serialize_payload_call(
                hiding_point_slot,
                note_setup_payload.hiding_point,
                setup_log,
            ),
        );

        hiding_point_slot
    }

    fn serialize_payload_call(
        hiding_point_slot: Field,
        hiding_point: Point,
        setup_log: [Field; 9],
    ) -> [Field; 13] {
        let log_count = 9;
        let point_count = 3; // TODO: import global POINT_LENGTH
        let total_size = 1 + point_count + log_count;

        // Initialize result array
        let mut result = [0 as Field; 13]; // TODO: use total_size
        let mut index = 0;

        // Add simple fields
        result[0] = hiding_point_slot;

        // Add point
        let point_data = hiding_point.serialize();
        for i in 0..point_count {
            index += 1;
            result[index] = point_data[i];
        }

        // Add log
        for i in 0..log_count {
            index += 1;
            result[index] = setup_log[i];
        }

        result
    }
}

pub mod AuthLib {
    use authwit::auth::{
        assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
    };
    use aztec::{context::{PrivateContext, PublicContext}, prelude::AztecAddress};

    pub fn _validate_from_private(from: AztecAddress, nonce: Field, context: &mut PrivateContext) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }

    pub fn _validate_from_public(context: &mut PublicContext, from: AztecAddress, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            // assert_current_call_valid_authwit_public(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }
}
