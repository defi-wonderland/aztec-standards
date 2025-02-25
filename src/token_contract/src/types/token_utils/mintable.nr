pub global MINTABLE_CODE: Quoted = quote {
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
};
