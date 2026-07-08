use crate::MultiToken;
use aztec::{
    oracle::random::random, protocol::address::AztecAddress,
    test::helpers::test_environment::TestEnvironment,
};
use compressed_string::FieldCompressedString;
use multitoken_authorization_contract::MultiTokenAuthorizationContract;
use multitoken_authorization_contract::MultiTokenAuthorizationContract::AuthCall;
use std::ops::WrappingSub;
use std::test::OracleMock;

/// Default mint amount used across the MultiToken test suite.
pub global mint_amount: u128 = 10_000 as u128;

/// @notice Sets up a TestEnvironment, three accounts (owner, recipient, minter), and a freshly-deployed MultiToken
/// wired with `minter` as the minter and the authorization hook disabled (`auth_contract == zero`).
/// @dev `with_account_contracts == false` uses fast light accounts (sufficient when no authwit is verified);
/// `true` deploys real account contracts (required when a private/public authwit is actually checked).
pub unconstrained fn setup_with_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let (owner, recipient, minter) = if with_account_contracts {
        let owner = env.create_contract_account();
        let recipient = env.create_contract_account();
        let minter = env.create_contract_account();
        (owner, recipient, minter)
    } else {
        let owner = env.create_light_account();
        let recipient = env.create_light_account();
        let minter = env.create_light_account();
        (owner, recipient, minter)
    };

    let multitoken_contract_address =
        deploy_multitoken_with_minter(&mut env, owner, minter, AztecAddress::zero());

    (env, multitoken_contract_address, owner, recipient, minter)
}

/// @notice Deploys a MultiToken via its only constructor (`constructor_with_minter`) and runs the public initializer.
/// @dev Single deploy shape (MultiToken has no initial-supply constructor and no `decimals`).
pub unconstrained fn deploy_multitoken_with_minter(
    env: &mut TestEnvironment,
    owner: AztecAddress,
    minter: AztecAddress,
    auth_contract: AztecAddress,
) -> AztecAddress {
    let initializer_call_interface = MultiToken::interface().constructor_with_minter(
        FieldCompressedString::from_string("TestMultiToken00000000000000000"),
        FieldCompressedString::from_string("TMT0000000000000000000000000000"),
        minter,
        auth_contract,
    );
    let multitoken_contract_address = env
        .deploy("@multitoken_contract/MultiToken")
        .with_public_initializer(owner, initializer_call_interface);

    multitoken_contract_address
}

/// @notice Setup + mint `mint_amount` of `id` to `owner`'s PRIVATE balance.
pub unconstrained fn setup_and_mint_to_private_with_minter(
    with_account_contracts: bool,
    id: Field,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (env, multitoken_contract_address, owner, recipient, minter) =
        setup_with_minter(with_account_contracts);

    mint_to_private(
        env,
        multitoken_contract_address,
        owner,
        id,
        mint_amount,
        minter,
    );

    (env, multitoken_contract_address, owner, recipient, minter)
}

/// @notice Setup + mint `mint_amount` of `id` to `owner`'s PUBLIC balance.
pub unconstrained fn setup_and_mint_to_public_with_minter(
    with_account_contracts: bool,
    id: Field,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (env, multitoken_contract_address, owner, recipient, minter) =
        setup_with_minter(with_account_contracts);

    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, mint_amount),
    );

    (env, multitoken_contract_address, owner, recipient, minter)
}

/// @notice Mints `amount` of `id` to `recipient`'s PRIVATE balance as `caller`.
/// @dev Mocks `getRandomField` before the private call so the inserted note's randomness is deterministic
/// (private-note creation requires this oracle mock).
pub unconstrained fn mint_to_private(
    env: TestEnvironment,
    multitoken_contract_address: AztecAddress,
    recipient: AztecAddress,
    id: Field,
    amount: u128,
    caller: AztecAddress,
) {
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    env.call_private(
        caller,
        MultiToken::at(multitoken_contract_address).mint_to_private(recipient, id, amount),
    );
}

/// @notice Asserts that `owner`'s PUBLIC balance of `id` equals `expected`.
pub unconstrained fn check_public_balance(
    env: TestEnvironment,
    multitoken_contract_address: AztecAddress,
    owner: AztecAddress,
    id: Field,
    expected: u128,
) {
    let amount = get_public_balance(env, multitoken_contract_address, owner, id);
    assert(amount == expected, "Public balance is not correct");
}

/// @notice Reads `owner`'s PUBLIC balance of `id` via the `balance_of_public` view.
pub unconstrained fn get_public_balance(
    env: TestEnvironment,
    multitoken_contract_address: AztecAddress,
    owner: AztecAddress,
    id: Field,
) -> u128 {
    env.view_public(MultiToken::at(multitoken_contract_address).balance_of_public(owner, id))
}

/// @notice Asserts that `owner`'s PRIVATE balance of `id` equals `expected`.
pub unconstrained fn check_private_balance(
    env: TestEnvironment,
    multitoken_contract_address: AztecAddress,
    owner: AztecAddress,
    id: Field,
    expected: u128,
) {
    let balance = get_private_balance(env, multitoken_contract_address, owner, id);
    assert(balance == expected, "Private balance is not correct");
}

/// @notice Reads `owner`'s PRIVATE balance of `id` via the `balance_of_private` utility.
pub unconstrained fn get_private_balance(
    env: TestEnvironment,
    multitoken_contract_address: AztecAddress,
    owner: AztecAddress,
    id: Field,
) -> u128 {
    env.execute_utility(MultiToken::at(multitoken_contract_address).balance_of_private(owner, id))
}

/// @notice Returns the u128 maximum value (used for overflow tests).
pub unconstrained fn max_u128() -> u128 {
    (0 as u128).wrapping_sub(1)
}

/// @notice Setup that wires a MultiTokenAuthorizationContract spy into the MultiToken, enabling the ARC-403 hook.
/// @dev The plain `setup_with_minter` passes `AztecAddress::zero()` (hook disabled); this one passes the spy address.
pub unconstrained fn setup_with_auth_contract_and_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let (owner, recipient, minter) = if with_account_contracts {
        let owner = env.create_contract_account();
        let recipient = env.create_contract_account();
        let minter = env.create_contract_account();
        (owner, recipient, minter)
    } else {
        let owner = env.create_light_account();
        let recipient = env.create_light_account();
        let minter = env.create_light_account();
        (owner, recipient, minter)
    };

    // Deploy the spy first (no initializer) so we can pass its address to the MultiToken constructor.
    let auth_contract_address = env
        .deploy("@multitoken_authorization_contract/MultiTokenAuthorizationContract")
        .without_initializer();

    let multitoken_contract_address =
        deploy_multitoken_with_minter(&mut env, owner, minter, auth_contract_address);

    (env, multitoken_contract_address, owner, recipient, minter, auth_contract_address)
}

/// @notice `setup_with_auth_contract_and_minter` + mint `mint_amount` of `id` to `owner`'s PRIVATE balance.
/// @dev `mint_to_private` does NOT fire the authorization hook by design, so on return `last_call.selector == 0`.
pub unconstrained fn setup_and_mint_to_private_with_auth(
    with_account_contracts: bool,
    id: Field,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (env, multitoken_contract_address, owner, recipient, minter, auth_contract_address) =
        setup_with_auth_contract_and_minter(with_account_contracts);

    mint_to_private(
        env,
        multitoken_contract_address,
        owner,
        id,
        mint_amount,
        minter,
    );

    (env, multitoken_contract_address, owner, recipient, minter, auth_contract_address)
}

/// @notice Setup with real account contracts, mint `mint_amount` of `id` to `owner`'s PRIVATE balance, and deploy a
/// GenericProxy so a forwarded call has a `msg_sender` different from `owner` (the condition that triggers private
/// authwit validation).
pub unconstrained fn setup_and_mint_to_private_with_proxy(
    id: Field,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, multitoken_contract_address, owner, recipient, minter) =
        setup_and_mint_to_private_with_minter(/* with_account_contracts */ true, id);
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
    (env, multitoken_contract_address, owner, recipient, minter, proxy)
}

/// @notice Same as above but mints to `owner`'s PUBLIC balance (for the public-source on-behalf cases).
pub unconstrained fn setup_and_mint_to_public_with_proxy(
    id: Field,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, multitoken_contract_address, owner, recipient, minter) =
        setup_and_mint_to_public_with_minter(/* with_account_contracts */ true, id);
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
    (env, multitoken_contract_address, owner, recipient, minter, proxy)
}

/// @notice Reads the last recorded authorization-hook invocation from the spy.
pub unconstrained fn get_last_auth_call(
    env: TestEnvironment,
    auth_contract: AztecAddress,
) -> AuthCall {
    env.view_public(MultiTokenAuthorizationContract::at(auth_contract).get_last_call())
}

/// @notice Asserts the spy recorded a call with the expected `from`, `id`, `amount`, `selector`, and hook variant.
/// @dev The MultiToken hook is id-bearing, so this also asserts the recorded `id`. A non-zero `selector`
/// signals the hook fired (default storage has `selector == 0`). `expected_from_public` is true iff the token
/// dispatched via `authorize_public` (a public-context fn), false for `authorize_private`.
pub unconstrained fn assert_auth_call(
    env: TestEnvironment,
    auth_contract: AztecAddress,
    expected_from: AztecAddress,
    expected_id: Field,
    expected_amount: u128,
    expected_selector: Field,
    expected_from_public: bool,
) {
    let last_call = get_last_auth_call(env, auth_contract);
    assert(
        last_call.selector != 0,
        "expected authorization hook to be called but it wasn't (selector is 0)",
    );
    assert(last_call.from == expected_from, "authorization hook recorded unexpected `from`");
    assert(last_call.id == expected_id, "authorization hook recorded unexpected `id`");
    assert(last_call.amount == expected_amount, "authorization hook recorded unexpected `amount`");
    assert(
        last_call.selector == expected_selector,
        "authorization hook recorded unexpected `selector`",
    );
    assert(
        last_call.from_public == expected_from_public,
        "authorization hook invoked via unexpected variant (authorize_private vs authorize_public)",
    );
}

/// @notice Asserts the spy did NOT record any hook invocation (a default `AuthCall` has `selector == 0`).
pub unconstrained fn assert_auth_not_called(env: TestEnvironment, auth_contract: AztecAddress) {
    let last_call = get_last_auth_call(env, auth_contract);
    assert(
        last_call.selector == 0,
        "expected authorization hook not to be called but it was (selector is non-zero)",
    );
}
