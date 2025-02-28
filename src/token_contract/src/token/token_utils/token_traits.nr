pub mod traits {
    use aztec::{
        context::PrivateContext,
        note::note_emission::OuterNoteEmission,
        prelude::{AztecAddress, Map, PublicContext, PublicImmutable, PublicMutable},
    };

    use balance_set::balance_set::BalanceSet;
    use uint_note::uint_note::UintNote;

    use compressed_string::FieldCompressedString;

    // Base trait for common token functionality regardless of context
    pub trait TokenBase {}

    // Trait for token operations in a public context
    pub trait PublicTokenOps: TokenBase {
        // Constructor method
        fn token_constructor(
            storage_name: PublicImmutable<FieldCompressedString, &mut PublicContext>,
            storage_symbol: PublicImmutable<FieldCompressedString, &mut PublicContext>,
            storage_decimals: PublicImmutable<u8, &mut PublicContext>,
            name: str<31>,
            symbol: str<31>,
            decimals: u8,
        );

        // Balance management
        fn increase_public_balance(
            public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
            to: AztecAddress,
            amount: U128,
        );

        fn decrease_public_balance(
            public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
            from: AztecAddress,
            amount: U128,
        );

        fn increase_total_supply(
            total_supply: PublicMutable<U128, &mut PublicContext>,
            amount: U128,
        );

        // Hiding point and note related
        fn increase_hiding_point_balance(
            context: &mut PublicContext,
            hiding_point_slot: Field,
            amount: U128,
        );

        fn store_payload_in_storage(
            context: &mut PublicContext,
            slot: Field,
            point: [Field; 3],
            setup_log: [Field; 9],
        );

        // Cross-domain operations
        fn finalize_transfer_public_to_private(
            context: &mut PublicContext,
            public_balances: Map<AztecAddress, PublicMutable<U128, &mut PublicContext>, &mut PublicContext>,
            from: AztecAddress,
            hiding_point_slot: Field,
            amount: U128,
        );

        fn finalize_mint_to_private(
            context: &mut PublicContext,
            total_supply: PublicMutable<U128, &mut PublicContext>,
            hiding_point_slot: Field,
            amount: U128,
        );
    }

    // Trait for token operations in a private context
    pub trait PrivateTokenOps: TokenBase {
        // Balance management
        fn increase_private_balance(
            private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
            to: AztecAddress,
            amount: U128,
        ) -> OuterNoteEmission<UintNote>;

        fn decrease_private_balance(
            context: &mut PrivateContext,
            private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
            account: AztecAddress,
            amount: U128,
            max_notes: u32,
        ) -> OuterNoteEmission<UintNote>;

        fn subtract_balance(
            context: &mut PrivateContext,
            private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
            account: AztecAddress,
            amount: U128,
            max_notes: u32,
        ) -> U128;

        // Cross-context operations
        fn private_increase_public_balance(
            context: &mut PrivateContext,
            to: AztecAddress,
            amount: U128,
        );

        fn private_decrease_public_balance(
            context: &mut PrivateContext,
            from: AztecAddress,
            amount: U128,
        );

        fn private_finalize_mint_to_private(
            context: &mut PrivateContext,
            hiding_point_slot: Field,
            amount: U128,
        );

        fn prepare_transfer_public_to_private(
            context: &mut PrivateContext,
            private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
            from: AztecAddress,
            to: AztecAddress,
        ) -> Field;
    }
}
