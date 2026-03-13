use aztec::macros::aztec;

#[aztec]
pub contract AuthorizationContract {
    use aztec::{macros::functions::external, protocol::address::AztecAddress};

    /// @notice Private authorization hook
    /// @param _from The address tokens are moved from (zero address for mints)
    /// @param _amount The amount of tokens being moved
    #[external("private")]
    fn authorize_private(_from: AztecAddress, _amount: u128) {
        // no-op: allow all operations
    }

    /// @notice Public authorization hook
    /// @param _from The address tokens are moved from (zero address for mints)
    /// @param _amount The amount of tokens being moved
    #[external("public")]
    fn authorize_public(_from: AztecAddress, _amount: u128) {
        // no-op: allow all operations
    }
}
