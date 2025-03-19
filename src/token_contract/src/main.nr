pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract Token {

    use aztec::{
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
        prelude::{AztecAddress, Map, PublicImmutable, PublicMutable},
        protocol_types::traits::{Hash, Serialize},
    };

    // compression library
    use compressed_string::FieldCompressedString;

    // encryption library
    use aztec::encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note;
    // balance notes library (NOTE: it needs to be same as in the token_utils.nr)
    use balance_set::balance_set::BalanceSet;
    // token & auth utils (TODO(#30): +mint-auth utils)
    use token::{auth_utils::AuthLib, token_utils::TokenLib};

    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    #[storage]
    struct Storage<Context> {
        // TODO: fix "is private and not visible from the current module" warning
        // TODO: why BalanceSet cannot be imported from TokenLib while FieldCompressedString can?
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

        TokenLib::increase_public_balance(storage.public_balances, to, initial_supply);
        TokenLib::increase_total_supply(storage.total_supply, initial_supply);
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
        AuthLib::validate_from_private(&mut context, from, nonce);

        TokenLib::decrease_private_balance(
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
        AuthLib::validate_from_private(&mut context, from, nonce);

        TokenLib::decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        )
            .emit(encode_and_encrypt_note(&mut context, from, from));

        Token::at(context.this_address()).increase_public_balance(to, amount).enqueue(&mut context);

        let hiding_point_slot = TokenLib::prepare_transfer_public_to_private(
            &mut context,
            storage.private_balances,
            from,
            to,
        );
        hiding_point_slot
    }

    #[private]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        AuthLib::validate_from_private(&mut context, from, nonce);

        TokenLib::decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        )
            .emit(encode_and_encrypt_note(&mut context, from, from));

        TokenLib::increase_private_balance(storage.private_balances, to, amount).emit(
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
        AuthLib::validate_from_private(&mut context, from, nonce);

        TokenLib::decrease_private_balance(
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
        AuthLib::validate_from_private(&mut context, from, nonce);

        Token::at(context.this_address()).decrease_public_balance(from, amount).enqueue(&mut context);

        TokenLib::increase_private_balance(storage.private_balances, to, amount).emit(
            encode_and_encrypt_note(&mut context, to, from),
        );
    }

    #[private]
    fn prepare_transfer_public_to_private(from: AztecAddress, to: AztecAddress) -> Field {
        TokenLib::prepare_transfer_public_to_private(
            &mut context,
            storage.private_balances,
            from,
            to,
        )
    }

    #[internal]
    #[private]
    fn _recurse_subtract_balance(account: AztecAddress, amount: U128) -> U128 {
        TokenLib::subtract_balance(
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
        AuthLib::validate_from_public(&mut context, from, nonce);
        TokenLib::decrease_public_balance(storage.public_balances, from, amount);
        TokenLib::increase_public_balance(storage.public_balances, to, amount);
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
        AuthLib::validate_from_public(&mut context, from, nonce);
        TokenLib::finalize_transfer_public_to_private(
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
        TokenLib::store_payload_in_storage(&mut context, slot, point, setup_log);
    }

    #[public]
    #[internal]
    fn increase_public_balance(to: AztecAddress, amount: U128) {
        TokenLib::increase_public_balance(storage.public_balances, to, amount);
    }

    #[public]
    #[internal]
    fn decrease_public_balance(from: AztecAddress, amount: U128) {
        TokenLib::decrease_public_balance(storage.public_balances, from, amount);
    }

    #[public]
    #[internal]
    fn increase_hiding_point_balance(hiding_point_slot: Field, amount: U128) {
        TokenLib::increase_hiding_point_balance(&mut context, hiding_point_slot, amount);
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
        let hiding_point_slot = TokenLib::prepare_transfer_public_to_private(
            &mut context,
            storage.private_balances,
            from,
            to,
        );

        Token::at(context.this_address())
            ._finalize_mint_to_private_unsafe(amount, hiding_point_slot)
            .enqueue(&mut context);
    }

    #[public]
    fn mint_to_public(to: AztecAddress, amount: U128) {
        let minter = storage.minter.read();
        assert(minter.eq(context.msg_sender()), "caller is not minter");

        TokenLib::increase_public_balance(storage.public_balances, to, amount);
        TokenLib::increase_total_supply(storage.total_supply, amount);
    }

    #[public]
    fn finalize_mint_to_private(amount: U128, hiding_point_slot: Field) {
        let minter = storage.minter.read();
        assert(minter.eq(context.msg_sender()), "caller is not minter");

        TokenLib::finalize_mint_to_private(
            &mut context,
            storage.total_supply,
            hiding_point_slot,
            amount,
        );
    }

    #[public]
    #[internal]
    fn _finalize_mint_to_private_unsafe(amount: U128, hiding_point_slot: Field) {
        TokenLib::finalize_mint_to_private(
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
        AuthLib::validate_from_private(&mut context, from, nonce);

        TokenLib::decrease_private_balance(
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
        AuthLib::validate_from_public(&mut context, from, nonce);
        TokenLib::decrease_public_balance(storage.public_balances, from, amount);
        TokenLib::decrease_total_supply(storage.total_supply, amount);
    }

    #[public]
    #[internal]
    fn decrease_total_supply(amount: U128) {
        TokenLib::decrease_total_supply(storage.total_supply, amount);
    }
}
