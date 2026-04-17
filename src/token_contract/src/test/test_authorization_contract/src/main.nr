use aztec::macros::aztec;

#[aztec]
pub contract AuthorizationContract {
    use aztec::{
        macros::{functions::{external, internal, only_self, view}, storage::storage},
        protocol::{address::AztecAddress, traits::{Deserialize, Packable, Serialize}},
    };
    use aztec::state_vars::PublicMutable;

    /// @notice Records the parameters of the last authorization hook invocation
    /// @dev Used by tests to assert that the token passes the expected arguments to the hook
    /// @param from The address whose balance was spent in the triggering token operation
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    /// @param called Whether the hook has been invoked at least once; distinguishes a real call from default storage values
    #[derive(Packable, Serialize, Deserialize)]
    pub struct AuthCall {
        pub from: AztecAddress,
        pub amount: u128,
        pub selector: Field,
        pub called: bool,
    }

    /// @notice Test-only storage used to verify hook invocations from the token contract
    /// @param last_call The parameters received on the most recent authorize_private or authorize_public call
    #[storage]
    struct Storage<Context> {
        last_call: PublicMutable<AuthCall, Context>,
        should_revert: PublicMutable<bool, Context>,
    }

    /// @notice Private authorization hook, called by the token in private context
    /// @param from The address whose balance is being spent
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("private")]
    fn authorize_private(from: AztecAddress, amount: u128, selector: Field) {
        // Storage writes are not allowed from private context, so we enqueue a public
        // call to record_call_internal, which forwards to _record_call.
        self.enqueue_self.record_call_internal(from, amount, selector)
    }

    /// @notice Public authorization hook, called by the token in public context
    /// @param from The address whose balance is being spent
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("public")]
    fn authorize_public(from: AztecAddress, amount: u128, selector: Field) {
        // Records the call synchronously. Allows all operations - this test contract never rejects.
        self.internal._record_call(from, amount, selector)
    }

    /// @notice Test-only setter to toggle whether the hook rejects incoming calls
    /// @dev When set to true, both authorize_private and authorize_public will revert
    /// @param value The new value for the should_revert flag
    #[external("public")]
    fn set_should_revert(value: bool) {
        self.storage.should_revert.write(value);
    }

    #[external("public")]
    #[view]
    fn get_last_call() -> AuthCall {
        self.storage.last_call.read()
    }

    /// @notice Public entrypoint for enqueued dispatch from authorize_private; shared write path lives in _record_call
    /// @param from The address whose balance was spent in the triggering token operation
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("public")]
    #[only_self]
    fn record_call_internal(from: AztecAddress, amount: u128, selector: Field) {
        self.internal._record_call(from, amount, selector);
    }

    /// @notice Test-only. Persists the parameters received by the authorization hook into public storage
    /// @dev Shared write path for both authorize_private (via record_call_internal) and authorize_public (via self.internal)
    /// @param from The address whose balance was spent in the triggering token operation
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[internal("public")]
    fn _record_call(from: AztecAddress, amount: u128, selector: Field) {
        // Test-only switch: when should_revert is true, simulate an authorization contract that rejects the call.
        assert(!self.storage.should_revert.read(), "operation not authorized");

        self.storage.last_call.write(AuthCall { from, amount, selector, called: true });
    }
}
