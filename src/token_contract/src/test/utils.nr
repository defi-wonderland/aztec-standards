use crate::Token;
use authorization_contract::AuthorizationContract;
use authorization_contract::AuthorizationContract::AuthCall;
use aztec::{
    note::{constants::MAX_NOTES_PER_PAGE, note_viewer_options::NoteViewerOptions},
    oracle::random::random,
    protocol::{address::AztecAddress, traits::Packable},
    state_vars::{OwnedStateVariable, PrivateSet},
    test::helpers::test_environment::TestEnvironment,
};
use std::ops::WrappingSub;
use std::test::OracleMock;
use uint_note::UintNote;

pub global mint_amount: u128 = 10_000 as u128;

pub unconstrained fn setup_with_initial_supply(
    with_account_contracts: bool,
    initial_supply: u128,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();

    let (owner, recipient) = if with_account_contracts {
        let owner = env.create_contract_account();
        let recipient = env.create_contract_account();
        (owner, recipient)
    } else {
        let owner = env.create_light_account();
        let recipient = env.create_light_account();
        (owner, recipient)
    };

    let token_contract_address = deploy_token_with_initial_supply(
        &mut env,
        owner,
        initial_supply,
        owner,
        AztecAddress::zero(),
    );

    (env, token_contract_address, owner, recipient)
}

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

    let token_contract_address =
        deploy_token_with_minter(&mut env, owner, minter, AztecAddress::zero());

    (env, token_contract_address, owner, recipient, minter)
}

pub unconstrained fn deploy_token_with_initial_supply(
    env: &mut TestEnvironment,
    owner: AztecAddress,
    initial_supply: u128,
    to: AztecAddress,
    auth_contract: AztecAddress,
) -> AztecAddress {
    // Deploy token contract
    let initializer_call_interface = Token::interface().constructor_with_initial_supply(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
        initial_supply,
        to,
        auth_contract,
    );
    let token_contract_address = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        initializer_call_interface,
    );

    token_contract_address
}

pub unconstrained fn deploy_token_with_minter(
    env: &mut TestEnvironment,
    owner: AztecAddress,
    minter: AztecAddress,
    auth_contract: AztecAddress,
) -> AztecAddress {
    // Deploy token contract
    let initializer_call_interface = Token::interface().constructor_with_minter(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
        minter,
        auth_contract,
    );
    let token_contract_address = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        initializer_call_interface,
    );

    token_contract_address
}

pub unconstrained fn setup_and_mint_to_public_without_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    // Setup
    let (env, token_contract_address, owner, recipient) =
        setup_with_initial_supply(with_account_contracts, mint_amount);

    (env, token_contract_address, owner, recipient)
}

pub unconstrained fn setup_and_mint_to_private_with_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (env, token_contract_address, owner, recipient, minter) =
        setup_with_minter(with_account_contracts);

    // Mint some tokens
    mint_to_private(env, token_contract_address, owner, mint_amount, minter);

    (env, token_contract_address, owner, recipient, minter)
}

pub unconstrained fn setup_and_mint_to_private_without_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    // Setup
    let (env, token_contract_address, owner, recipient) =
        setup_with_initial_supply(with_account_contracts, mint_amount);

    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_public_to_private(owner, owner, mint_amount, 0),
    );

    (env, token_contract_address, owner, recipient)
}

pub unconstrained fn mint_to_private(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
    caller: AztecAddress,
) {
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    env.call_private(caller, Token::at(token_contract_address).mint_to_private(recipient, amount));
}

pub unconstrained fn check_public_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
    address_amount: u128,
) {
    let amount: u128 = get_public_balance(env, token_contract_address, address);
    assert(amount == address_amount, "Public balance is not correct");
}

pub unconstrained fn get_public_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
) -> u128 {
    let amount = env.view_public(Token::at(token_contract_address).balance_of_public(address));
    amount
}

pub unconstrained fn check_total_supply(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    expected_total_supply: u128,
) {
    let total_supply: u128 = get_total_supply(env, token_contract_address);
    assert(total_supply == expected_total_supply, "Total supply is not correct");
}

pub unconstrained fn get_total_supply(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
) -> u128 {
    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    total_supply
}

pub unconstrained fn check_private_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
    address_amount: u128,
) {
    let balance_of_private = get_private_balance(env, token_contract_address, address);
    assert(balance_of_private == address_amount, "Private balance is not correct");
}

pub unconstrained fn get_private_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
) -> u128 {
    let amt = env.execute_utility(Token::at(token_contract_address).balance_of_private(address));
    amt
}

pub unconstrained fn get_private_balance_notes(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    account: AztecAddress,
    offset: u32,
) -> BoundedVec<UintNote, MAX_NOTES_PER_PAGE> {
    let notes = env.utility_context_at(token_contract_address, |context| {
        let options =
            NoteViewerOptions::<UintNote, <UintNote as Packable>::N>::new().set_offset(offset);
        let private_balances_slot = Token::storage_layout().private_balances.slot;
        let set: PrivateSet<UintNote, _> =
            OwnedStateVariable::new(context, private_balances_slot, account);
        let notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> = set.view_notes(options);
        notes
    });

    notes
}

// While authwits authorize a contract to perform an action, spending private notes still requires
// knowledge of the note secrets. For private tokens, the note owner must be involved in the
// transaction -- they cannot simply give another user an authwit and have that user spend the notes
// independently. We deploy a proxy contract so that msg_sender in the target differs from the
// caller, which is the condition that triggers authwit validation. We can't use another account for
// this, since different scopes are enforced by TXE.
pub unconstrained fn setup_and_mint_to_private_with_proxy() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, token_contract_address, owner, recipient) =
        setup_and_mint_to_private_without_minter(/* with_account_contracts */ true);
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
    (env, token_contract_address, owner, recipient, proxy)
}

pub unconstrained fn setup_and_mint_to_public_with_proxy() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, token_contract_address, owner, recipient) =
        setup_and_mint_to_public_without_minter(/* with_account_contracts */ true);
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
    (env, token_contract_address, owner, recipient, proxy)
}

// @notice Returns the u128 maximum value
pub unconstrained fn max_u128() -> u128 {
    (0 as u128).wrapping_sub(1)
}

// Test-only setup that wires an AuthorizationContract into the token, enabling the ARC-403
// authorization hook. The default setup helpers above pass `AztecAddress::zero()` to the token,
// which disables the hook.
pub unconstrained fn setup_with_auth_contract(
    with_account_contracts: bool,
    initial_supply: u128,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();

    let (owner, recipient) = if with_account_contracts {
        let owner = env.create_contract_account();
        let recipient = env.create_contract_account();
        (owner, recipient)
    } else {
        let owner = env.create_light_account();
        let recipient = env.create_light_account();
        (owner, recipient)
    };

    // Deploy the test authorization contract first (no initializer) so we can pass its address
    // to the token constructor.
    let auth_contract_address =
        env.deploy("@test_authorization_contract/AuthorizationContract").without_initializer();

    let token_contract_address = deploy_token_with_initial_supply(
        &mut env,
        owner,
        initial_supply,
        owner,
        auth_contract_address,
    );

    (env, token_contract_address, owner, recipient, auth_contract_address)
}

// @notice Deploys the auth contract, deploys the token wired to it via `constructor_with_minter`,
// and mints `mint_amount` to the owner's private balance.
// @dev `mint_to_private` does not trigger the authorization hook by design (see ARC-403 tech design),
// so after this helper returns `last_call.selector` is still 0 (default).
pub unconstrained fn setup_and_mint_to_private_with_auth(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (env, token_contract_address, owner, recipient, minter, auth_contract_address) =
        setup_with_auth_contract_and_minter(with_account_contracts);

    mint_to_private(env, token_contract_address, owner, mint_amount, minter);

    (env, token_contract_address, owner, recipient, minter, auth_contract_address)
}

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

    // Deploy the test authorization contract first (no initializer) so we can pass its address
    // to the token constructor.
    let auth_contract_address =
        env.deploy("@test_authorization_contract/AuthorizationContract").without_initializer();

    let token_contract_address =
        deploy_token_with_minter(&mut env, owner, minter, auth_contract_address);

    (env, token_contract_address, owner, recipient, minter, auth_contract_address)
}

// @notice Reads the last recorded authorization hook invocation from the test AuthorizationContract
pub unconstrained fn get_last_auth_call(
    env: TestEnvironment,
    auth_contract: AztecAddress,
) -> AuthCall {
    env.view_public(AuthorizationContract::at(auth_contract).get_last_call())
}

// @notice Asserts the test AuthorizationContract recorded a call with the expected `from`, `amount`,
// selector, and hook variant (private vs public).
// @dev A non-zero selector signals the hook was invoked; default storage has selector == 0.
// `expected_from_public` encodes the ARC-403 dispatch table: true if the token called authorize_public,
// false if it called authorize_private.
pub unconstrained fn assert_auth_call(
    env: TestEnvironment,
    auth_contract: AztecAddress,
    expected_from: AztecAddress,
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

// @notice Asserts the test AuthorizationContract did NOT record any hook invocation
// @dev A default-initialized `AuthCall` has `selector == 0`, which is not a valid token selector,
// so `selector == 0` unambiguously means the hook was never called.
pub unconstrained fn assert_auth_not_called(env: TestEnvironment, auth_contract: AztecAddress) {
    let last_call = get_last_auth_call(env, auth_contract);
    assert(
        last_call.selector == 0,
        "expected authorization hook not to be called but it was (selector is non-zero)",
    );
}
