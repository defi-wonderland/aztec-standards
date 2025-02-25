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

        TokenLib::_private_finalize_mint_to_private(&mut context, amount, hiding_point_slot);
    }

    #[public]
    fn mint_to_public(to: AztecAddress, amount: U128) {
        TokenLib::_increase_public_balance(storage.public_balances, to, amount);
        let supply = storage.total_supply.read().add(amount);
        storage.total_supply.write(supply);
    }

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
};
