pub mod TokenLib {
    use aztec::{
        context::PrivateContext,
        note::{note_emission::OuterNoteEmission, note_interface::PartialNote},
        oracle::random::random,
        prelude::{AztecAddress, Map, Point, PublicContext, PublicImmutable, PublicMutable},
        protocol_types::{abis::function_selector::FunctionSelector, traits::{ToField, Serialize}},
    };

    use balance_set::balance_set::BalanceSet;
    use uint_note::uint_note::{UintNote, PartialUintNote};

    use compressed_string::FieldCompressedString;

    pub fn token_constructor(
        storage_name: PublicImmutable<FieldCompressedString, &mut PublicContext>,
        storage_symbol: PublicImmutable<FieldCompressedString, &mut PublicContext>,
        storage_decimals: PublicImmutable<u8, &mut PublicContext>,
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
    ) {
        storage_name.initialize(FieldCompressedString::from_string(name));
        storage_symbol.initialize(FieldCompressedString::from_string(symbol));
        storage_decimals.initialize(decimals);
    }

    /** ==========================================================
     * ======================= LIBRARIES =========================
     * ======================================================== */

    pub fn finalize_transfer_public_to_private(
        context: &mut PublicContext,
        public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        partial_note: PartialUintNote,
        amount: u128,
    ) {
        decrease_public_balance(public_balances, from, amount);
        increase_hiding_point_balance(context, partial_note, amount);
    }

    pub fn decrease_private_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: u128,
        max_notes: u32,
    ) -> OuterNoteEmission<UintNote> {
        let change = subtract_balance(context, private_balances, account, amount, max_notes);
        increase_private_balance(private_balances, account, change)
    }

    pub fn increase_private_balance(
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        to: AztecAddress,
        amount: u128,
    ) -> OuterNoteEmission<UintNote> {
        private_balances.at(to).add(to, amount)
    }

    pub fn increase_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        to: AztecAddress,
        amount: u128,
    ) {
        let new_balance = public_balances.at(to).read() + amount;
        public_balances.at(to).write(new_balance);
    }

    pub fn decrease_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        amount: u128,
    ) {
        let new_balance = public_balances.at(from).read() - amount;
        public_balances.at(from).write(new_balance);
    }

    pub fn increase_hiding_point_balance(
        context: &mut PublicContext,
        partial_note: PartialUintNote,
        amount: u128,
    ) {
        partial_note.complete(amount, context);
    }

    pub fn subtract_balance(
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

            // NOTE: hacky way to call itself before Token is compiled to be used as a library.
            // let self = Token::at(context.this_address());
            // self._recurse_subtract_balance(account, remaining).call(context)

            let result: u128 = context
                .call_private_function(
                    context.this_address(),
                    FunctionSelector::from_signature(
                        "_recurse_subtract_balance((Field),(Field,Field))",
                    ),
                    [] // serialize_recurse_subtract_balance_call(account, remaining),
                )
                .get_preimage();

            result as u128 // TODO: test this works
        }
    }

    pub fn private_increase_public_balance(
        context: &mut PrivateContext,
        to: AztecAddress,
        amount: u128,
    ) {
        // let self = Token::at(context.this_address());
        // self.increase_public_balance(to, amount).enqueue(&mut context);
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("increase_public_balance((Field),(Field,Field))"),
            [] // serialize_balance_change_call(to, amount),
        );
    }

    pub fn private_decrease_public_balance(
        context: &mut PrivateContext,
        from: AztecAddress,
        amount: u128,
    ) {
        // let self = Token::at(context.this_address());
        // self.decrease_public_balance(from, amount).enqueue(&mut context);
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("decrease_public_balance((Field),(Field,Field))"),
            [] // serialize_balance_change_call(from, amount),
        );
    }

    pub fn private_increase_hiding_point_balance(
        context: &mut PrivateContext,
        partial_note: PartialUintNote,
        amount: u128,
    ) {
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("increase_hiding_point_balance(Field,(Field,Field))"),
            [] // serialize_hiding_point_balance_change_call(partial_note, amount),
        );
    }

    pub fn finalize_mint_to_private(
        context: &mut PublicContext,
        total_supply: PublicMutable<u128, &mut PublicContext>,
        partial_note: PartialUintNote,
        amount: u128,
    ) {
        increase_total_supply(total_supply, amount);
        increase_hiding_point_balance(context, partial_note, amount);
    }

    pub fn private_finalize_mint_to_private(
        context: &mut PrivateContext,
        partial_note: PartialUintNote,
        amount: u128,
    ) {
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("finalize_mint_to_private((Field,Field),Field)"),
            []
            // serialize_finalization_call(amount.serialize(), partial_note.commitment()),
        );
    }

    pub fn increase_total_supply(
        total_supply: PublicMutable<u128, &mut PublicContext>,
        amount: u128,
    ) {
        let new_supply = total_supply.read() + amount;
        total_supply.write(new_supply);
    }

    pub fn store_payload_in_storage(
        context: &mut PublicContext,
        partial_note: PartialUintNote,
    ) {
        context.storage_write(partial_note.commitment(), true);
    }

    pub fn prepare_transfer_public_to_private(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress, // sender of the tag: TODO(#9887): this is not great?
        to: AztecAddress,
    ) -> PartialUintNote {

        let partial_note = UintNote::partial(
            to,
            private_balances.at(to).set.storage_slot,
            context,
            to,
            from,
        );

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("store_payload_in_storage(Field,[Field;3],[Field;9])"),
            []
            // serialize_payload_call(
            //     partial_note,
            // ),
        );

        partial_note
    }

    /** ==========================================================
     * ======================= SERIALIZATION =====================
     * ======================================================== */

    // NOTE: it's painful to manually serialize call arguments

    fn serialize_payload_call(
        partial_note: PartialUintNote,
    ) {
        // TODO: re-do serialization
    }

    fn serialize_recurse_subtract_balance_call(account: AztecAddress, amount: u128) {
        // TODO: re-do serialization
    }

    fn serialize_finalization_call(amount: [Field; 1], partial_note: PartialUintNote) {
        // TODO: re-do serialization
    }

    fn serialize_balance_change_call(account: AztecAddress, amount: u128) {
        // TODO: re-do serialization
    }

    fn serialize_hiding_point_balance_change_call(
        partial_note: PartialUintNote,
        amount: u128,
    ) {
        // TODO: re-do serialization
    }
}
