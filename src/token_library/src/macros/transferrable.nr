pub global TRANSFERRABLE_CODE: Quoted = quote {
    
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;
    
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
        AuthLib::_validate_from_private(from, nonce, &mut context);

        TokenLib::_decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        )
            .emit(encode_and_encrypt_note(&mut context, from, from));

        TokenLib::_private_increase_public_balance(&mut context, to, amount);
    }

    #[private]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        AuthLib::_validate_from_private(from, nonce, &mut context);

        TokenLib::_decrease_private_balance(
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

    #[private]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        AuthLib::_validate_from_private(from, nonce, &mut context);

        TokenLib::_private_decrease_public_balance(&mut context, from, amount);

        TokenLib::_increase_private_balance(storage.private_balances, to, amount).emit(
            encode_and_encrypt_note(&mut context, to, from),
        );
    }

    #[private]
    fn prepare_transfer_public_to_private(from: AztecAddress, to: AztecAddress) -> Field {
        TokenLib::_prepare_transfer_public_to_private(
            &mut context,
            storage.private_balances,
            from,
            to,
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
        AuthLib::_validate_from_public(&mut context, from, nonce);
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
        AuthLib::_validate_from_public(&mut context, from, nonce);
        TokenLib::_finalize_transfer_public_to_private(
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
        TokenLib::_store_payload_in_storage(&mut context, slot, point, setup_log);
    }

    #[public]
    #[internal]
    fn increase_public_balance(to: AztecAddress, amount: U128) {
        TokenLib::_increase_public_balance(storage.public_balances, to, amount);
    }

    #[public]
    #[internal]
    fn decrease_public_balance(from: AztecAddress, amount: U128) {
        TokenLib::_decrease_public_balance(storage.public_balances, from, amount);
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
    
};
