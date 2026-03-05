use aztec::macros::aztec;

#[aztec]
pub contract AuthorizationContract {
    use aztec::{macros::functions::external, protocol::address::AztecAddress};

    /// @notice Private authorization hook - called in private context when the source balance is private
    /// @dev In production: validate against a private allowlist, KYC note, etc.
    /// @param _from The address tokens are moved from (zero address for mints)
    /// @param _to The address tokens are moved to (zero address for burns / commitment transfers)
    /// @param _amount The amount of tokens being moved
    #[external("private")]
    fn authorize_private(_from: AztecAddress, _to: AztecAddress, _amount: u128) {
        // no-op: allow all operations
    }

    /// @notice Public authorization hook - called in public context when the source balance is public
    /// @dev In production: validate against a public allowlist, compliance registry, etc.
    /// @param _from The address tokens are moved from (zero address for mints)
    /// @param _to The address tokens are moved to (zero address for burns / commitment transfers)
    /// @param _amount The amount of tokens being moved
    #[external("public")]
    fn authorize_public(_from: AztecAddress, _to: AztecAddress, _amount: u128) {
        // no-op: allow all operations
    }
}
