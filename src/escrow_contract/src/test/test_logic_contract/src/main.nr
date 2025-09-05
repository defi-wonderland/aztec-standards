use aztec::macros::aztec;

#[aztec]
contract TestLogic {
    // aztec library
    use aztec::{
        macros::{events::event, functions::{initializer, private, public}, storage::storage},
        prelude::{AztecAddress, PublicImmutable},
        protocol_types::public_keys::PublicKeys,
    };
    use escrow_contract::library::logic::{
        _check_escrow, _secret_keys_to_public_keys, _share_escrow, _withdraw, _withdraw_nft,
    };

    /// @notice Data privately emitted to an account that will use the escrow
    /// @dev We declare the event struct here to expose it in the abi as macro event cannot be used in libraries, only in contracts
    /// @param escrow The address of the escrow
    /// @param nsk_m The escrow nullifier secret key
    /// @param ivsk_m The escrow incoming viewing key
    /// @param ovsk_m The escrow outgoing viewing key
    /// @param tsk_m The escrow transaction secret key
    #[event]
    struct EscrowDetailsLogContent {
        escrow: AztecAddress,
        nsk_m: Field,
        ivsk_m: Field,
        ovsk_m: Field,
        tsk_m: Field,
    }

    // @param escrow_class_id The contract class id of the escrow contract
    #[storage]
    struct Storage<Context> {
        escrow_class_id: PublicImmutable<Field, Context>,
    }

    /// @dev Initialize the contract
    /// @param escrow_class_id The contract class id of the escrow contract
    #[public]
    #[initializer]
    fn constructor(escrow_class_id: Field) {
        storage.escrow_class_id.initialize(escrow_class_id);
    }

    /// @notice Verifies that the keys correspond to the escrow address and that the escrow instance data is correct.
    /// @dev Reverts if the data is not correct.
    /// @param escrow The address of the escrow
    /// @param nsk_m The escrow nullifier secret key
    /// @param ivsk_m The escrow incoming viewing key
    /// @param ovsk_m The escrow outgoing viewing key
    /// @param tsk_m The escrow transaction secret key
    #[private]
    fn check_escrow(
        escrow: AztecAddress,
        nsk_m: Field,
        ivsk_m: Field,
        ovsk_m: Field,
        tsk_m: Field,
    ) {
        _check_escrow(
            &mut context,
            escrow,
            storage.escrow_class_id.read(),
            nsk_m,
            ivsk_m,
            ovsk_m,
            tsk_m,
        );
    }

    /// @notice Shares the escrow details needed to find and use the escrow contract
    /// @dev Emits a private log with the escrow details
    /// @param account The address of the account that will receive the escrow details
    /// @param escrow The address of the escrow
    /// @param nsk_m The escrow nullifier secret key
    /// @param ivsk_m The escrow incoming viewing key
    /// @param ovsk_m The escrow outgoing viewing key
    /// @param tsk_m The escrow transaction secret key
    #[private]
    fn share_escrow(
        account: AztecAddress,
        escrow: AztecAddress,
        nsk_m: Field,
        ivsk_m: Field,
        ovsk_m: Field,
        tsk_m: Field,
    ) {
        _share_escrow(&mut context, account, escrow, nsk_m, ivsk_m, ovsk_m, tsk_m);
    }

    /// @notice Withdraws an amount of tokens from the provided escrow.
    /// @param escrow The address of the escrow
    /// @param account The address of the account that will receive the tokens
    /// @param token The address of the token
    /// @param amount The amount of tokens to withdraw from the escrow
    #[private]
    fn withdraw(escrow: AztecAddress, account: AztecAddress, token: AztecAddress, amount: u128) {
        _withdraw(&mut context, escrow, account, token, amount);
    }

    /// @notice Withdraws an NFT from the provided escrow.
    /// @param escrow The address of the escrow
    /// @param account The address of the account that will receive the NFT
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

    /// @notice Derives public keys from secret keys.
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
}
