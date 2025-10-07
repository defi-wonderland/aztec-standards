use aztec::macros::aztec;
mod test;

#[aztec]
pub contract TokenCaller {
    use aztec::macros::functions::{initializer, private, public};
    use aztec::protocol_types::address::AztecAddress;
    use token::Token;

    #[public]
    #[initializer]
    fn constructor() {}

    /// @notice Checks if the private balance of the caller has at least `amount`
    /// @param token_address The address of the token contract
    /// @param amount The amount of tokens to check
    /// @return True if the private balance of the caller has at least `amount`, false otherwise
    #[private]
    fn has_private_balance(token_address: AztecAddress, amount: u128) -> bool {
        let token = Token::at(token_address);
        token.has_private_balance(context.msg_sender(), amount).call(&mut context)
    }

    /// @notice Returns the private balance of the caller
    /// @param token_address The address of the token contract
    /// @return The private balance of the caller
    #[private]
    fn private_balance_of(token_address: AztecAddress) -> u128 {
        let token = Token::at(token_address);
        token.private_balance_of(context.msg_sender()).call(&mut context)
    }
}
