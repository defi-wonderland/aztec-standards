use aztec::macros::aztec;

#[aztec]
pub contract AuthorizationContract {
    use aztec::{macros::functions::external, protocol::address::AztecAddress};

    /// @notice Private authorization hook - called by the token in private context
    /// @dev No-op implementation for testing: allows all operations
    /// @param _from The address tokens are moved from (zero for mints)
    /// @param _amount The amount of tokens being moved
    #[external("private")]
    fn authorize_private(_from: AztecAddress, _amount: u128) {}

    /// @notice Public authorization hook - called by the token in public context
    /// @dev No-op implementation for testing: allows all operations
    /// @param _from The address tokens are moved from (zero for mints)
    /// @param _amount The amount of tokens being moved
    #[external("public")]
    fn authorize_public(_from: AztecAddress, _amount: u128) {}
}
