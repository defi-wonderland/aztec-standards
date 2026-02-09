mod test;

use aztec::macros::aztec;

#[aztec]
contract TestLogic {
    // aztec library
    use aztec::{
        macros::{events::event, functions::{external, initializer}, storage::storage},
        protocol_types::{address::AztecAddress, public_keys::PublicKeys},
        state_vars::public_immutable::PublicImmutable,
    };
    use escrow_contract::derivation::keys::secret_key_to_public_keys;
    use escrow_contract::library::logic::{_get_escrow, _share_escrow, _withdraw, _withdraw_nft};

    /// @notice Data privately emitted to an account that will use the escrow
    /// @dev We declare the event struct here to expose it in the abi as macro event cannot be declared in libraries, only in contracts
    /// @dev See to library/logic.nr _share_escrow function for the event emission implementation
    /// @dev #[allow(dead_code)] added because is used because EscrowDetailsLogContent is defined for logging but not directly instantiated.
    /// @param escrow The address of the escrow
    /// @param secret_key The secret key used to derive master secret keys and public keys
    #[event]
    #[allow(dead_code)]
    struct EscrowDetailsLogContent {
        escrow: AztecAddress,
        secret_key: Field,
    }

    // @param escrow_class_id The contract class id of the escrow contract
    #[storage]
    struct Storage<Context> {
        escrow_class_id: PublicImmutable<Field, Context>,
    }

    /// @dev Initialize the contract
    /// @param escrow_class_id The contract class id of the escrow contract
    #[external("public")]
    #[initializer]
    fn constructor(escrow_class_id: Field) {
        self.storage.escrow_class_id.initialize(escrow_class_id);
    }

    /// @notice Returns the escrow address that corresponds to the given secret key and class ID.
    /// @param secret_key The secret key used to derive master secret keys and public keys
    /// @return The escrow address
    #[external("private")]
    fn get_escrow(secret_key: Field) -> AztecAddress {
        _get_escrow(
            self.context,
            self.storage.escrow_class_id.read(),
            secret_key,
        )
    }

    /// @notice Shares the escrow details needed to find and use the escrow contract
    /// @dev Emits a private log with the escrow details
    /// @param account The address of the account that will receive the escrow details
    /// @param escrow The address of the escrow
    /// @param secret_key The secret key used to derive master secret keys and public keys
    #[external("private")]
    fn share_escrow(account: AztecAddress, escrow: AztecAddress, secret_key: Field) {
        _share_escrow(self.context, account, escrow, secret_key);
    }

    /// @notice Withdraws an amount of tokens from the provided escrow.
    /// @param escrow The address of the escrow
    /// @param account The address of the account that will receive the tokens
    /// @param token The address of the token
    /// @param amount The amount of tokens to withdraw from the escrow
    #[external("private")]
    fn withdraw(escrow: AztecAddress, account: AztecAddress, token: AztecAddress, amount: u128) {
        _withdraw(self.context, escrow, account, token, amount);
    }

    /// @notice Withdraws an NFT from the provided escrow.
    /// @param escrow The address of the escrow
    /// @param account The address of the account that will receive the NFT
    /// @param nft The address of the NFT contract
    /// @param token_id The id of the token to withdraw from the escrow
    #[external("private")]
    fn withdraw_nft(
        escrow: AztecAddress,
        account: AztecAddress,
        nft: AztecAddress,
        token_id: Field,
    ) {
        _withdraw_nft(self.context, escrow, account, nft, token_id);
    }

    /// @notice Derives public keys from a secret key.
    /// @param secret_key The secret key used to derive master secret keys and public keys
    /// @return PublicKeys containing the derived public keys.
    #[external("private")]
    fn secret_keys_to_public_keys(secret_key: Field) -> PublicKeys {
        secret_key_to_public_keys(secret_key)
    }
}
