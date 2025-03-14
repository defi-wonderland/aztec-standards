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
        AuthLib::validate_from_private(&mut context, from, nonce);

        TokenLib::decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        )
            .emit(encode_and_encrypt_note(&mut context, from, from));

        TokenLib::private_increase_public_balance(&mut context, to, amount);
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

        TokenLib::private_increase_public_balance(&mut context, to, amount);

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

        TokenLib::private_increase_hiding_point_balance(&mut context, hiding_point_slot, amount);
    }

    #[private]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        AuthLib::validate_from_private(&mut context, from, nonce);

        TokenLib::private_decrease_public_balance(&mut context, from, amount);

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
    fn increase_hiding_point_balance(
        hiding_point_slot: Field,
        amount: U128,
    ) {
        TokenLib::increase_hiding_point_balance(
            &mut context,
            hiding_point_slot,
            amount,
        );
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
