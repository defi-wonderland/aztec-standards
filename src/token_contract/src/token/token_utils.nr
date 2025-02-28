pub mod token_traits;
use token_traits::traits::{PrivateTokenOps, PublicTokenOps, TokenBase, TokenSerialization};

use aztec::{
    context::PrivateContext,
    note::{note_emission::OuterNoteEmission, note_interface::PartialNote},
    oracle::random::random,
    prelude::{AztecAddress, Map, Point, PublicContext, PublicImmutable, PublicMutable},
    protocol_types::abis::function_selector::FunctionSelector,
};

use balance_set::balance_set::BalanceSet;
use uint_note::uint_note::UintNote;

use compressed_string::FieldCompressedString;

// Implementation struct for TokenLib that implements all the traits
pub struct TokenLib;

// Implementation of PublicTokenOps for TokenLib
impl PublicTokenOps for TokenLib {
    fn token_constructor(
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

    fn increase_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
        to: AztecAddress,
        amount: U128,
    ) {
        let new_balance = public_balances.at(to).read().add(amount);
        public_balances.at(to).write(new_balance);
    }

    fn decrease_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        amount: U128,
    ) {
        let new_balance = public_balances.at(from).read().sub(amount);
        public_balances.at(from).write(new_balance);
    }

    fn increase_total_supply(total_supply: PublicMutable<U128, &mut PublicContext>, amount: U128) {
        let new_supply = total_supply.read().add(amount);
        total_supply.write(new_supply);
    }

    fn increase_hiding_point_balance(
        context: &mut PublicContext,
        hiding_point_slot: Field,
        amount: U128,
    ) {
        let finalization_payload =
            UintNote::finalization_payload().new(context, hiding_point_slot, amount);
        finalization_payload.emit();
    }

    fn store_payload_in_storage(
        context: &mut PublicContext,
        slot: Field,
        point: [Field; 3],
        setup_log: [Field; 9],
    ) {
        context.storage_write(slot, point);
        context.storage_write(slot + aztec::protocol_types::point::POINT_LENGTH as Field, setup_log);
    }

    fn finalize_transfer_public_to_private(
        context: &mut PublicContext,
        public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        hiding_point_slot: Field,
        amount: U128,
    ) {
        Self::decrease_public_balance(public_balances, from, amount);
        Self::increase_hiding_point_balance(context, hiding_point_slot, amount);
    }

    fn finalize_mint_to_private(
        context: &mut PublicContext,
        total_supply: PublicMutable<U128, &mut PublicContext>,
        hiding_point_slot: Field,
        amount: U128,
    ) {
        Self::increase_total_supply(total_supply, amount);
        Self::increase_hiding_point_balance(context, hiding_point_slot, amount);
    }
}

// Implementation of PrivateTokenOps for TokenLib
impl PrivateTokenOps for TokenLib {
    fn increase_private_balance(
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        to: AztecAddress,
        amount: U128,
    ) -> OuterNoteEmission<UintNote> {
        private_balances.at(to).add(to, amount)
    }

    fn decrease_private_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: U128,
        max_notes: u32,
    ) -> OuterNoteEmission<UintNote> {
        let change = Self::subtract_balance(context, private_balances, account, amount, max_notes);
        Self::increase_private_balance(private_balances, account, change)
    }

    fn subtract_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: U128,
        max_notes: u32,
    ) -> U128 {
        let subtracted = private_balances.at(account).try_sub(amount, max_notes);
        assert(subtracted > U128::zero(), "Balance too low");

        if subtracted >= amount {
            subtracted - amount
        } else {
            let remaining = amount - subtracted;
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

    fn private_increase_public_balance(
        context: &mut PrivateContext,
        to: AztecAddress,
        amount: U128,
    ) {
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("increase_public_balance((Field),(Field,Field))"),
            Self::serialize_balance_change_call(to, amount.serialize()),
        );
    }

    fn private_decrease_public_balance(
        context: &mut PrivateContext,
        from: AztecAddress,
        amount: U128,
    ) {
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("decrease_public_balance((Field),(Field,Field))"),
            Self::serialize_balance_change_call(from, amount.serialize()),
        );
    }

    fn private_finalize_mint_to_private(
        context: &mut PrivateContext,
        hiding_point_slot: Field,
        amount: U128,
    ) {
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("finalize_mint_to_private((Field,Field),Field)"),
            Self::serialize_finalization_call(amount.serialize(), hiding_point_slot),
        );
    }

    fn prepare_transfer_public_to_private(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
    ) -> Field {
        let to_note_slot = private_balances.at(to).set.storage_slot;
        let note_randomness = unsafe { random() };
        let note_setup_payload = UintNote::setup_payload().new(to, note_randomness, to_note_slot);
        let setup_log = note_setup_payload.encrypt_log(context, to, from);
        let hiding_point_slot = note_setup_payload.hiding_point.x;

        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("store_payload_in_storage(Field,[Field;3],[Field;9])"),
            Self::serialize_payload_call(
                hiding_point_slot,
                note_setup_payload.hiding_point,
                setup_log,
            ),
        );

        hiding_point_slot
    }
}

// Implementation of TokenBase for TokenLib (just to complete the trait hierarchy)
impl TokenBase for TokenLib {}

// Implementation of TokenSerialization for TokenLib
impl TokenSerialization for TokenLib {
    fn serialize_payload_call(
        hiding_point_slot: Field,
        hiding_point: Point,
        setup_log: [Field; 9],
    ) -> [Field; 13] {
        let log_count = 9;
        let point_count = 3; // TODO: import global POINT_LENGTH
        let total_size = 1 + point_count + log_count;

        let mut result = [0 as Field; 13];
        let mut index = 0;

        result[0] = hiding_point_slot;

        let point_data = hiding_point.serialize();
        for i in 0..point_count {
            index += 1;
            result[index] = point_data[i];
        }

        for i in 0..log_count {
            index += 1;
            result[index] = setup_log[i];
        }

        result
    }

    fn serialize_finalization_call(amount: [Field; 2], hiding_point_slot: Field) -> [Field; 3] {
        let mut result = [0 as Field; 3];
        result[0] = amount[0];
        result[1] = amount[1];
        result[2] = hiding_point_slot;
        result
    }

    fn serialize_balance_change_call(account: AztecAddress, amount: [Field; 2]) -> [Field; 3] {
        let mut result = [0 as Field; 3];
        result[0] = account.to_field();
        result[1] = amount[0];
        result[2] = amount[1];
        result
    }
}
