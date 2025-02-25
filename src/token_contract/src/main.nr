mod types;
mod test;

use crate::types::token_utils::token_utils;
use dep::aztec::macros::aztec;

#[token_utils]
#[aztec]
pub contract Token {

    use dep::compressed_string::FieldCompressedString;
    use dep::std::ops::{Add, Sub};

    use dep::aztec::{
        encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note,
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
        prelude::{AztecAddress, Map, PublicImmutable, PublicMutable},
        protocol_types::{point::Point, traits::{Hash, Serialize}},
    };

    // TODO: move authwit to token_utils ?
    use dep::authwit::auth::assert_current_call_valid_authwit_public;

    use crate::types::balance_set::BalanceSet;
    use crate::types::token_utils::TokenLib;

    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<U128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<U128, Context>, Context>,
    }

    #[public]
    #[initializer]
    fn constructor(name: str<31>, symbol: str<31>, decimals: u8) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.decimals.initialize(decimals);
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
        TokenLib::_validate_from_private(from, nonce, &mut context);

        TokenLib::_subtract_exact_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        )
            .emit(encode_and_encrypt_note(&mut context, from, from));

        let self = Token::at(context.this_address());
        self.increase_public_balance(to, amount).enqueue(&mut context);
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

        let self = Token::at(context.this_address());
        self.decrease_public_balance(from, amount).enqueue(&mut context);

        TokenLib::_increase_private_balance(storage.private_balances, to, amount).emit(
            encode_and_encrypt_note(&mut context, to, from),
        );
    }

    /// Prepares an increase of private balance of `to` (partial note). The increase needs to be finalized by calling
    /// some of the finalization functions (`finalize_transfer_public_to_private`, `finalize_mint_to_private`).
    /// Returns a hiding point slot.
    #[private]
    fn prepare_transfer_public_to_private(to: AztecAddress, from: AztecAddress) -> Field {
        // TODO(#9887): ideally we'd not have `from` here, but we do need a `from` address to produce a tagging secret
        // with `to`.
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

    pub(crate) unconstrained fn balance_of_private(owner: AztecAddress) -> pub U128 {
        storage.private_balances.at(owner).balance_of()
    }

    /** ==========================================================
     * ======================= MINTABLE ==========================
     * ======================================================== */

    /// Mints token `amount` to a private balance of `to`. Message sender has to have minter permissions (checked
    /// in the enqueued call).
    #[private]
    fn mint_to_private(
        from: AztecAddress, // sender of the tag: TODO(#9887): this is not great?
        to: AztecAddress,
        amount: U128,
    ) {
        // We prepare the partial note to which we'll "send" the minted amount.
        let hiding_point_slot = TokenLib::_prepare_transfer_public_to_private(
            from,
            to,
            &mut context,
            storage.private_balances,
        );

        let self: Token = Token::at(context.this_address());

        // At last we finalize the mint. Usage of the `unsafe` method here is safe because we set the `from`
        // function argument to a message sender, guaranteeing that only a message sender with minter permissions
        // can successfully execute the function.
        self
            ._finalize_mint_to_private_unsafe(context.msg_sender(), amount, hiding_point_slot)
            .enqueue(&mut context);
    }

    #[public]
    fn mint_to_public(to: AztecAddress, amount: U128) {
        TokenLib::_increase_public_balance(storage.public_balances, to, amount);
        let supply = storage.total_supply.read().add(amount);
        storage.total_supply.write(supply);
    }

    /// Finalizes a mint of token `amount` to a private balance of `to`. The mint must be prepared by calling
    /// `prepare_transfer_public_to_private` first and the resulting
    /// `hiding_point_slot` must be passed as an argument to this function.
    ///
    /// Note: This function is only an optimization as it could be replaced by a combination of `mint_to_public`
    /// and `finalize_transfer_public_to_private`. It is however used very commonly so it makes sense to optimize it
    /// (e.g. used during token bridging, in AMM liquidity token etc.).
    #[public]
    fn finalize_mint_to_private(amount: U128, hiding_point_slot: Field) {
        TokenLib::_finalize_mint_to_private(
            amount,
            hiding_point_slot,
            &mut context,
            storage.total_supply,
        );
    }

    #[public]
    #[internal]
    fn _finalize_mint_to_private_unsafe(
        from: AztecAddress,
        amount: U128,
        hiding_point_slot: Field,
    ) {
        TokenLib::_finalize_mint_to_private(
            amount,
            hiding_point_slot,
            &mut context,
            storage.total_supply,
        );
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    #[private]
    fn burn_private(from: AztecAddress, amount: U128, nonce: Field) {
        TokenLib::_validate_from_private(from, nonce, &mut context);

        storage.private_balances.at(from).sub(from, amount).emit(encode_and_encrypt_note(
            &mut context,
            from,
            from,
        ));
        let self = Token::at(context.this_address());
        self._reduce_total_supply(amount).enqueue(&mut context);
    }

    #[public]
    fn burn_public(from: AztecAddress, amount: U128, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
        TokenLib::_decrease_public_balance(storage.public_balances, from, amount);
        let self = Token::at(context.this_address());
        self._reduce_total_supply(amount).call(&mut context);
    }

    #[public]
    #[internal]
    fn _reduce_total_supply(amount: U128) {
        // Only to be called from burn.
        let new_supply = storage.total_supply.read().sub(amount);
        storage.total_supply.write(new_supply);
    }

}
