use aztec::macros::aztec;

#[aztec]
pub contract TestLogic {
    // aztec library
    use aztec::{
        macros::{functions::{initializer, private, public}, storage::storage},
        prelude::{AztecAddress, PublicImmutable, PrivateContext},
        protocol_types::{
            public_keys::PublicKeys,
        },
        event::event_interface::{emit_event_in_private_log, PrivateLogContent},
        oracle::get_contract_instance::get_contract_instance,
        protocol_types::{
            contract_instance::ContractInstance,
            public_keys::{IvpkM, NpkM, OvpkM, TpkM},
            traits::ToField,
        },
        std::embedded_curve_ops::{EmbeddedCurvePoint, EmbeddedCurveScalar, fixed_base_scalar_mul},
    };

    /// @notice Data privately emitted to an account that will use the escrow
    /// @param escrow The address of the escrow
    /// @param keys The escrow keys [nsk_m, ivsk_m, ovsk_m, tsk_m]
    #[event]
    struct EscrowDetailsLogContent {
        escrow: AztecAddress,
        keys: [Field; 4],
    }

    // @param owner The address of the owner
    // @param escrow_class_id The contract class id of the escrow contract
    #[storage]
    struct Storage<Context> {
        owner: PublicImmutable<AztecAddress, Context>,
        escrow_class_id: PublicImmutable<Field, Context>,
    }

    /// @dev Initialize the contract
    /// @param owner The address of the owner
    /// @param escrow_class_id The contract class id of the escrow contract
    #[public]
    #[initializer]
    fn constructor(owner: AztecAddress, escrow_class_id: Field) {
        storage.owner.initialize(owner);
        storage.escrow_class_id.initialize(escrow_class_id);
    }

    /// @notice Checks that the escrow details are correct
    /// @param escrow The address of the escrow
    /// @param keys The escrow keys [nsk_m, ivsk_m, ovsk_m, tsk_m]
    #[private]
    fn check_escrow(
        escrow: AztecAddress,
        keys: [Field; 4],
    ) {
        _check_escrow(context, escrow, keys, storage.escrow_class_id.read());
    }

    /// @notice Shares the escrow details with the recipient
    /// @param escrow The address of the escrow
    /// @param keys The escrow keys [nsk_m, ivsk_m, ovsk_m, tsk_m]
    /// @param account The address of the account that will use the escrow
    #[private]
    fn share_escrow(
        escrow: AztecAddress,
        keys: [Field; 4],
        account: AztecAddress,
    ) {
        let event = EscrowDetailsLogContent { escrow, keys };
        _share_escrow(&mut context, event, account);
    }

    /// @notice Withdraws an amount of tokens from the escrow
    /// @param escrow The address of the escrow
    /// @param account The address of the account that will use the escrow
    /// @param token The address of the token
    /// @param amount The amount of tokens to withdraw from the escrow
    #[private]
    fn withdraw(
        escrow: AztecAddress,
        account: AztecAddress,
        token: AztecAddress,
        amount: u128,
    ) {
        _withdraw(&mut context, escrow, account, token, amount);
    }

    /// @notice Withdraws an NFT from the escrow
    /// @param escrow The address of the escrow
    /// @param account The address of the account that will use the escrow
    /// @param nft The address of the NFT contract
    /// @param token_id The id of the token to withdraw from the escrow
    #[private]
    fn withdraw_nft(
        escrow: AztecAddress,
        account: AztecAddress,
        nft: AztecAddress,
        token_id: Field,
    ) {
        _withdraw_nft(&mut context, escrow, account, nft, token_id);
    }

    /// @notice Derives public keys from secret keys
    /// @param nsk_m Master Nullifier Secret Key
    /// @param ivsk_m Incoming Viewing Key
    /// @param ovsk_m Outgoing Viewing Key
    /// @param tsk_m Transaction Secret Key
    /// @return PublicKeys containing the derived public keys.
    #[private]
    fn secret_keys_to_public_keys(
        nsk_m: Field,
        ivsk_m: Field,
        ovsk_m: Field,
        tsk_m: Field,
    ) -> PublicKeys {
        _secret_keys_to_public_keys(nsk_m, ivsk_m, ovsk_m, tsk_m)
    }

    /** ==========================================================
     * =================== LOGIC LIBRARIES =======================
     * ======================================================== */

    /// @notice Verifies that the keys correspond to the escrow address and that the
    ///         escrow instance data is correct.
    /// @dev Reverts if the data is not correct.
    /// @param context The private context
    /// @param escrow The address of the escrow
    /// @param keys The escrow keys [nsk_m, ivsk_m, ovsk_m, tsk_m]
    /// @param escrow_class_id The contract class id of the escrow contract
    #[private]
    fn _check_escrow(
        context: PrivateContext,
        escrow: AztecAddress,
        keys: [Field; 4],
        escrow_class_id: Field,
    ) {
        // Get the escrow instance
        let escrow_instance: ContractInstance = get_contract_instance(escrow);

        // Compute the public keys from the secret keys
        let computed_public_keys: PublicKeys =
            _secret_keys_to_public_keys(keys[0], keys[1], keys[2], keys[3]);

        // Check the public keys are computed correctly
        assert_eq(computed_public_keys, escrow_instance.public_keys, "Public keys do not match");

        // Force the initialization hash and deployer to be null
        assert_eq(
            escrow_instance.initialization_hash,
            0,
            "Escrow initialization hash should be null",
        );
        assert_eq(escrow_instance.deployer.to_field(), 0, "Escrow deployer should be null");

        // Check the class id is correct
        assert_eq(
            escrow_instance.contract_class_id.to_field(),
            escrow_class_id,
            "Escrow class id does not match",
        );

        // Force the salt to be equal to the address of the logic contract (this contract)
        assert_eq(
            escrow_instance.salt,
            context.this_address().to_field(),
            "Escrow salt should be equal to the this address",
        );
    }

    /// @notice Shares the escrow details needed to find and use the escrow contract
    /// @dev Emits a private log with the escrow details
    /// @param context The private context
    /// @param escrow The address of the escrow
    /// @param keys The escrow keys [nsk_m, ivsk_m, ovsk_m, tsk_m]
    /// @param account The address of the account that will use the escrow
    #[private]
    fn _share_escrow(
        context: &mut PrivateContext,
        event: EscrowDetailsLogContent,
        account: AztecAddress,
    ) {
        // Emit the encrypted event to the recipient
        emit_event_in_private_log(
            event,
            context,
            context.msg_sender(),
            account,
            PrivateLogContent.CONSTRAINED_ENCRYPTION,
        );
    }

    /// @notice Withdraws an amount of tokens from the provided escrow.
    /// @param escrow The address of the escrow
    /// @param account The address of the account that will use the escrow
    /// @param token The address of the token
    /// @param amount The amount of tokens to withdraw from the escrow
    #[private]
    fn _withdraw(
        context: &mut PrivateContext,
        escrow: AztecAddress,
        account: AztecAddress,
        token: AztecAddress,
        amount: u128,
    ) {
        // For now, just a placeholder - you'll need to implement the actual escrow interaction
        // Escrow::at(escrow).withdraw(token, amount, account).call(context);
    }

    /// @notice Withdraws an NFT from the provided escrow.
    /// @param escrow The address of the escrow
    /// @param account The address of the account that will use the escrow
    /// @param nft The address of the NFT contract
    /// @param token_id The id of the token to withdraw from the escrow
    #[private]
    fn _withdraw_nft(
        context: &mut PrivateContext,
        escrow: AztecAddress,
        account: AztecAddress,
        nft: AztecAddress,
        token_id: Field,
    ) {
        // For now, just a placeholder - you'll need to implement the actual escrow interaction
        // Escrow::at(escrow).withdraw_nft(nft, token_id, account).call(context);
    }

    /// @notice Derives public keys from secret keys.
    /// @param nsk_m Master Nullifier Secret Key
    /// @param ivsk_m Incoming Viewing Key
    /// @param ovsk_m Outgoing Viewing Key
    /// @param tsk_m Transaction Secret Key
    /// @return PublicKeys containing the derived public keys.
    #[private]
    fn _secret_keys_to_public_keys(
        nsk_m: Field,
        ivsk_m: Field,
        ovsk_m: Field,
        tsk_m: Field,
    ) -> PublicKeys {
        let npk_m: EmbeddedCurvePoint =
            fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(nsk_m));
        let ivpk_m: EmbeddedCurvePoint =
            fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(ivsk_m));
        let ovpk_m: EmbeddedCurvePoint =
            fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(ovsk_m));
        let tpk_m: EmbeddedCurvePoint =
            fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(tsk_m));

        PublicKeys {
            npk_m: NpkM { inner: npk_m },
            ivpk_m: IvpkM { inner: ivpk_m },
            ovpk_m: OvpkM { inner: ovpk_m },
            tpk_m: TpkM { inner: tpk_m },
        }
    }
}
