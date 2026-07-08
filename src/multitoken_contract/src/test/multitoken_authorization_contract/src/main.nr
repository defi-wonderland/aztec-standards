use aztec::macros::aztec;

/// @notice Minimal ARC-403 authorization-hook contract with the id-bearing MultiToken hook signature.
/// @dev The MultiToken hook adds an `id: Field` parameter to the standard ARC-403 hook, so the repo's id-less
/// `AuthorizationContract` cannot be reused verbatim. This contract provides the id-bearing interface that the
/// MultiToken contract's hook call sites are generated against. It is disabled-by-default in MultiToken
/// (`auth_contract == zero`), so a deployment that never wires it remains unaffected. No test logic lives here.
#[aztec]
pub contract MultiTokenAuthorizationContract {
    use aztec::{
        macros::{functions::{external, internal, only_self, view}, storage::storage},
        protocol::{address::AztecAddress, traits::{Deserialize, Packable, Serialize}},
        state_vars::PublicMutable,
    };

    /// @notice Records the parameters of the last authorization hook invocation
    /// @param from The address whose balance was spent in the triggering token operation
    /// @param id The token id being moved
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    /// @param from_public Whether the hook was invoked through authorize_public (true) or authorize_private (false)
    #[derive(Packable, Serialize, Deserialize)]
    pub struct AuthCall {
        pub from: AztecAddress,
        pub id: Field,
        pub amount: u128,
        pub selector: Field,
        pub from_public: bool,
    }

    /// @notice Storage used to record hook invocations from the MultiToken contract
    /// @param last_call The parameters received on the most recent authorize_private or authorize_public call
    /// @param should_revert When true, both authorize_private and authorize_public will revert
    #[storage]
    struct Storage<Context> {
        last_call: PublicMutable<AuthCall, Context>,
        should_revert: PublicMutable<bool, Context>,
    }

    /// @notice Private authorization hook, called by the token in private context
    /// @param from The address whose balance is being spent
    /// @param id The token id being moved
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("private")]
    fn authorize_private(from: AztecAddress, id: Field, amount: u128, selector: Field) {
        // Storage writes are not allowed from private context, so we enqueue a public call to record_call_internal,
        // which forwards to _record_call.
        self.enqueue_self.record_call_internal(from, id, amount, selector)
    }

    /// @notice Public authorization hook, called by the token in public context
    /// @param from The address whose balance is being spent
    /// @param id The token id being moved
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("public")]
    fn authorize_public(from: AztecAddress, id: Field, amount: u128, selector: Field) {
        self.internal._record_call(from, id, amount, selector, true)
    }

    /// @notice Setter to toggle whether the hook rejects incoming calls
    /// @param value The new value for the should_revert flag
    #[external("public")]
    fn set_should_revert(value: bool) {
        self.storage.should_revert.write(value);
    }

    /// @notice Test-only reader for the most recent recorded hook invocation
    /// @return The parameters of the last authorize_private or authorize_public call
    #[external("public")]
    #[view]
    fn get_last_call() -> AuthCall {
        self.storage.last_call.read()
    }

    /// @notice Public entrypoint for enqueued dispatch from authorize_private; shared write path lives in _record_call
    /// @param from The address whose balance was spent in the triggering token operation
    /// @param id The token id being moved
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("public")]
    #[only_self]
    fn record_call_internal(from: AztecAddress, id: Field, amount: u128, selector: Field) {
        self.internal._record_call(from, id, amount, selector, false);
    }

    /// @notice Persists the parameters received by the authorization hook into public storage
    /// @param from The address whose balance was spent in the triggering token operation
    /// @param id The token id being moved
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    /// @param from_public True if the caller is authorize_public, false if the caller is authorize_private
    #[internal("public")]
    fn _record_call(
        from: AztecAddress,
        id: Field,
        amount: u128,
        selector: Field,
        from_public: bool,
    ) {
        assert(!self.storage.should_revert.read(), "operation not authorized");

        self.storage.last_call.write(AuthCall { from, id, amount, selector, from_public });
    }
}
