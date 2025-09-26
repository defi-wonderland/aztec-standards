mod types;
mod test;
mod logic;

use aztec::macros::aztec;

#[aztec]
pub contract Escrow {
    // aztec library
    use aztec::{
        context::PrivateContext,
        macros::functions::private,
        oracle::get_contract_instance::get_contract_instance,
        prelude::AztecAddress,
        protocol_types::{contract_instance::ContractInstance, traits::{FromField, ToField}},
    };
    // External contract interfaces
    use dep::nft_contract::NFT;
    use dep::token_contract::Token;

    /// @notice Withdraws tokens from the escrow contract to the recipient
    /// @dev Only callable by the Logic contract address encoded in the salt
    /// @param token The address of the token contract
    /// @param amount The amount of tokens to withdraw
    /// @param recipient The address to receive the tokens
    #[private]
    fn withdraw(token: AztecAddress, amount: u128, recipient: AztecAddress) {
        // Extract Logic contract address from salt and verify access control
        _validate_logic_contract_access(&mut context);

        // Transfer tokens from escrow to recipient with nonce zero
        Token::at(token)
            .transfer_private_to_private(context.this_address(), recipient, amount, 0)
            .call(&mut context);
    }

    /// @notice Withdraws an NFT from the escrow contract to the recipient
    /// @dev Only callable by the Logic contract address encoded in the salt
    /// @param nft The address of the NFT contract
    /// @param token_id The ID of the token to withdraw
    /// @param recipient The address to receive the NFT
    #[private]
    fn withdraw_nft(nft: AztecAddress, token_id: Field, recipient: AztecAddress) {
        // Extract Logic contract address from salt and verify access control
        _validate_logic_contract_access(&mut context);

        // Transfer NFT from escrow to recipient with nonce zero
        NFT::at(nft)
            .transfer_private_to_private(context.this_address(), recipient, token_id, 0)
            .call(&mut context);
    }

    /// @notice Validates that the caller is the Logic contract with enhanced security checks
    /// @dev Performs multiple verification layers beyond just msg_sender check
    #[contract_library_method]
    fn _validate_logic_contract_access(context: &mut PrivateContext) {
        let instance: ContractInstance = get_contract_instance(context.this_address());
        let logic_contract_address = AztecAddress::from_field(instance.salt);

        // PRIMARY: Check msg_sender matches Logic contract address from salt
        assert(
            context.msg_sender() == logic_contract_address,
            "Escrow: unauthorized caller - only Logic contract allowed",
        );

        // ENHANCED SECURITY: Verify contract class ID is not zero (valid deployment)
        assert(instance.contract_class_id.to_field() != 0, "Escrow: invalid contract class ID");

        // ENHANCED SECURITY: Verify deployer is canonical deployer (prevents malicious deployments)
        let canonical_deployer = AztecAddress::from_field(0);
        assert(
            instance.deployer == canonical_deployer,
            "Escrow: must be deployed by canonical deployer",
        );

        // ENHANCED SECURITY: Verify contract is properly initialized
        assert(instance.initialization_hash != 0, "Escrow: contract must be properly initialized");

        // ENHANCED SECURITY: Additional validation that salt actually contains a valid address
        assert(
            logic_contract_address != AztecAddress::from_field(0),
            "Escrow: Logic contract address in salt cannot be zero",
        );
    }
}
