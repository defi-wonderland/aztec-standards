use aztec::macros::aztec;

#[aztec]
pub contract AuthorizationContract {
    use aztec::{macros::functions::external, protocol::address::AztecAddress};

    /// @notice Private authorization hook - called in private context when the source balance is private
    /// @param _from The address tokens are moved from (zero address for mints)
    /// @param _amount The amount of tokens being moved
    #[external("private")]
    fn authorize_private(_from: AztecAddress, _amount: u128) {
        // no-op: allow all operations
    }

    /// @notice Public authorization hook - called in public context when the source balance is public
    /// @param _from The address tokens are moved from (zero address for mints)
    /// @param _amount The amount of tokens being moved
    #[external("public")]
    fn authorize_public(_from: AztecAddress, _amount: u128) {
        // no-op: allow all operations
    }
}
