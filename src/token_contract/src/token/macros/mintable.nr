pub global MINTABLE_CODE: Quoted = quote {
    // TODO(#30): add authentication using some MintLib
    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

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

        TokenLib::_private_finalize_mint_to_private(&mut context, hiding_point_slot, amount);
    }

    #[public]
    fn mint_to_public(to: AztecAddress, amount: U128) {
        TokenLib::_increase_public_balance(storage.public_balances, to, amount);
        TokenLib::_increase_total_supply(storage.total_supply, amount);
    }

    #[public]
    fn finalize_mint_to_private(amount: U128, hiding_point_slot: Field) {
        TokenLib::_finalize_mint_to_private(
            &mut context,
            storage.total_supply,
            hiding_point_slot,
            amount,
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
            &mut context,
            storage.total_supply,
            hiding_point_slot,
            amount,
        );
    }
};
