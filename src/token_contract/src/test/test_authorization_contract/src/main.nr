use aztec::macros::aztec;

#[aztec]
pub contract AuthorizationContract {
    use aztec::{macros::functions::external, protocol::address::AztecAddress};

    /// @notice Private authorization hook, called by the token in private context
    /// @param from The address whose balance is being spent
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("private")]
    fn authorize_private(from: AztecAddress, amount: u128, selector: Field) {
        // no-op: allow all operations
    }

    /// @notice Public authorization hook, called by the token in public context
    /// @param from The address whose balance is being spent
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("public")]
    fn authorize_public(from: AztecAddress, amount: u128, selector: Field) {
        // no-op: allow all operations
    }
}
