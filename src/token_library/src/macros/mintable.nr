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
            &mut context,
            storage.private_balances,
            from,
            to,
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

    // TODO(#29): implement burnable
    // /** ==========================================================
    //  * ======================= BURNABLE ==========================
    //  * ======================================================== */

    // #[private]
    // fn burn_private(from: AztecAddress, amount: U128, nonce: Field) {
    //     _validate_from_private(from, nonce, &mut context);

    //     storage.private_balances.at(from).sub(from, amount).emit(encode_and_encrypt_note(
    //         &mut context,
    //         from,
    //         from,
    //     ));
    //     let self = Token::at(context.this_address());
    //     self._reduce_total_supply(amount).enqueue(&mut context);
    // }

    // #[public]
    // fn burn_public(from: AztecAddress, amount: U128, nonce: Field) {
    //     if (!from.eq(context.msg_sender())) {
    //         assert_current_call_valid_authwit_public(&mut context, from);
    //     } else {
    //         assert(nonce == 0, "invalid nonce");
    //     }
    //     _decrease_public_balance(storage, from, amount);
    //     let self = Token::at(context.this_address());
    //     self._reduce_total_supply(amount).call(&mut context);
    // }

    // #[public]
    // #[internal]
    // fn _reduce_total_supply(amount: U128) {
    //     // Only to be called from burn.
    //     let new_supply = storage.total_supply.read().sub(amount);
    //     storage.total_supply.write(new_supply);
    // }
};
