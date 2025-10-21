mod test;

use aztec::macros::aztec;

#[aztec]
contract TestLogic {
    // aztec library
    use aztec::{
        macros::{events::event, functions::{initializer, private, public}, storage::storage},
        oracle::get_contract_instance::get_contract_instance,
        protocol_types::{
            address::AztecAddress, contract_instance::ContractInstance, public_keys::PublicKeys,
        },
        state_vars::public_immutable::PublicImmutable,
    };
    use escrow_contract::library::logic::{
        _check_escrow, _secret_keys_to_public_keys, _share_escrow, _withdraw, _withdraw_nft,
        MasterSecretKeys,
    };

    /// @notice Data privately emitted to an account that will use the escrow
    /// @dev We declare the event struct here to expose it in the abi as macro event cannot be declared in libraries, only in contracts
    /// @dev See to library/logic.nr _share_escrow function for the event emission implementation
    /// @param escrow The address of the escrow
    /// @param master_secret_keys The master secret keys
    #[event]
    struct EscrowDetailsLogContent {
        escrow: AztecAddress,
        master_secret_keys: MasterSecretKeys,
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
    /// @param master_secret_keys The master secret keys
    #[private]
    fn check_escrow(escrow: AztecAddress, master_secret_keys: MasterSecretKeys) {
        _check_escrow(
            &mut context,
            escrow,
            storage.escrow_class_id.read(),
            master_secret_keys,
        );
    }

    /// @notice Shares the escrow details needed to find and use the escrow contract
    /// @dev Emits a private log with the escrow details
    /// @param account The address of the account that will receive the escrow details
    /// @param escrow The address of the escrow
    /// @param master_secret_keys The master secret keys
    #[private]
    fn share_escrow(
        account: AztecAddress,
        escrow: AztecAddress,
        master_secret_keys: MasterSecretKeys,
    ) {
        _share_escrow(&mut context, account, escrow, master_secret_keys);
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
    /// @param master_secret_keys The master secret keys
    /// @return PublicKeys containing the derived public keys.
    #[private]
    fn secret_keys_to_public_keys(master_secret_keys: MasterSecretKeys) -> PublicKeys {
        _secret_keys_to_public_keys(master_secret_keys)
    }
}
