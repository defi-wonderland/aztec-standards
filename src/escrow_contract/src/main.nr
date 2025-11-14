pub mod test;
pub mod library;
pub mod types;

use aztec::macros::aztec;

#[aztec]
pub contract Escrow {
    use aztec::{
        macros::functions::{external, internal},
        oracle::get_contract_instance::get_contract_instance,
        protocol_types::{
            address::AztecAddress, contract_instance::ContractInstance, traits::FromField,
        },
    };
    use nft::NFT;
    use token::Token;

    /// @notice Withdraws an amount from the escrow's private balance to the
    ///         recipient's private balance.
    /// @dev Can only be called by the corresponding Logic contract
    /// @param token The address of the token
    /// @param amount The amount of tokens to withdraw from the escrow
    /// @param recipient The address of the recipient
    #[external("private")]
    fn withdraw(token: AztecAddress, amount: u128, recipient: AztecAddress) {
        self.internal._assert_msg_sender();

        self.call(Token::at(token).transfer_private_to_private(self.address, recipient, amount, 0));
    }

    /// @notice Withdraws a token of a given ID from the escrow's private balance to
    ///         the recipient's private balance
    /// @dev Can only be called by the corresponding Logic contract
    /// @param nft The address of the NFT contract
    /// @param token_id The id of the token to withdraw from the escrow
    /// @param recipient The address of the recipient
    #[external("private")]
    fn withdraw_nft(nft: AztecAddress, token_id: Field, recipient: AztecAddress) {
        self.internal._assert_msg_sender();

        self.call(NFT::at(nft).transfer_private_to_private(self.address, recipient, token_id, 0));
    }

    /// @notice Asserts that the caller is the one encoded into the contract instance salt
    #[internal("private")]
    fn _assert_msg_sender() {
        let msg_sender = self.msg_sender().unwrap();
        let escrow_instance: ContractInstance = get_contract_instance(self.address);
        assert(
            AztecAddress::from_field(escrow_instance.salt) == msg_sender,
            "Not Authorized",
        );
    }
}
