/// @notice Tests that every token operation works correctly when an ARC-403 authorization
///         contract is set. The no-op AuthorizationContract allows all operations through, so
///         these tests verify that the hook machinery is wired correctly without restricting flow.
///
///         Two separate authorization flows are exercised:
///           - Private auth  (authorize_private): triggered when the source balance is private.
///             Runs as a direct cross-contract private call - nothing is revealed on-chain.
///           - Public auth (authorize_public): triggered when the source balance is public.
///             Runs in public context (the balance change is already visible on-chain anyway).
///             For functions that originate in private context but spend public balance
///             (transfer_public_to_private), the auth call is enqueued to public.
use crate::{test::utils, Token};
use aztec::{
    oracle::random::random, protocol::address::AztecAddress,
    test::helpers::test_environment::TestEnvironment,
};
use std::test::OracleMock;

global mint_amount: u128 = 10_000 as u128;

// ---------------------------------------------------------------------------
// Setup helpers
// ---------------------------------------------------------------------------

/// Deploys the no-op AuthorizationContract and a Token (constructor_with_minter).
/// No tokens are minted - used for tests that exercise the mint functions themselves.
/// Returns (env, token, owner, recipient, minter, auth).
unconstrained fn setup_with_auth_and_minter() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();
    let recipient = env.create_light_account();
    let minter = env.create_light_account();

    let auth_contract =
        env.deploy("@test_authorization_contract/AuthorizationContract").without_initializer();

    let token = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        Token::interface().constructor_with_minter(
            "TestToken0000000000000000000000",
            "TT00000000000000000000000000000",
            18,
            minter,
            auth_contract,
        ),
    );

    (env, token, owner, recipient, minter, auth_contract)
}

/// Deploys the no-op AuthorizationContract and a Token with `mint_amount` pre-minted to
/// `owner` in the **public** balance. Used for tests whose source balance is public.
/// Returns (env, token, owner, recipient, auth).
unconstrained fn setup_with_auth_and_public_balance() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();
    let recipient = env.create_light_account();

    let auth_contract =
        env.deploy("@test_authorization_contract/AuthorizationContract").without_initializer();

    let token = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        Token::interface().constructor_with_initial_supply(
            "TestToken0000000000000000000000",
            "TT00000000000000000000000000000",
            18,
            mint_amount,
            owner,
            auth_contract,
        ),
    );

    (env, token, owner, recipient, auth_contract)
}

/// Deploys the no-op AuthorizationContract and a Token with `mint_amount` pre-minted to
/// `owner` in the **private** balance. Used for tests whose source balance is private.
/// Returns (env, token, owner, recipient, auth).
unconstrained fn setup_with_auth_and_private_balance() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();
    let recipient = env.create_light_account();
    let minter = env.create_light_account();

    let auth_contract =
        env.deploy("@test_authorization_contract/AuthorizationContract").without_initializer();

    let token = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        Token::interface().constructor_with_minter(
            "TestToken0000000000000000000000",
            "TT00000000000000000000000000000",
            18,
            minter,
            auth_contract,
        ),
    );

    utils::mint_to_private(env, token, owner, mint_amount, minter);

    (env, token, owner, recipient, auth_contract)
}

// ---------------------------------------------------------------------------
// View - sanity checks
// ---------------------------------------------------------------------------

#[test]
unconstrained fn auth_contract_address_is_stored() {
    let (env, token, _, _, _, auth_contract) = setup_with_auth_and_minter();
    let stored = env.view_public(Token::at(token).get_auth_contract());
    assert(stored.eq(auth_contract), "auth_contract address mismatch");
}

#[test]
unconstrained fn auth_contract_zero_when_not_set() {
    let (env, token, _, _, _) = utils::setup_with_minter(false);
    let stored = env.view_public(Token::at(token).get_auth_contract());
    assert(stored.eq(AztecAddress::zero()), "expected zero address");
}

// ---------------------------------------------------------------------------
// Mint - private auth (destination is private)
// ---------------------------------------------------------------------------

/// mint_to_private: destination is private -> private auth
#[test]
unconstrained fn mint_to_private_with_auth() {
    let (mut env, token, owner, _, minter, _) = setup_with_auth_and_minter();
    utils::mint_to_private(env, token, owner, mint_amount, minter);
    utils::check_private_balance(env, token, owner, mint_amount);
    utils::check_total_supply(env, token, mint_amount);
}

/// mint_to_commitment: destination is private via commitment -> private auth
#[test]
unconstrained fn mint_to_commitment_with_auth() {
    let (mut env, token, _, recipient, minter, _) = setup_with_auth_and_minter();

    let commitment = env.call_private(
        minter,
        Token::at(token).initialize_transfer_commitment(recipient, minter),
    );

    env.call_public(minter, Token::at(token).mint_to_commitment(commitment, mint_amount));

    utils::check_private_balance(env, token, recipient, mint_amount);
    utils::check_total_supply(env, token, mint_amount);
}

// ---------------------------------------------------------------------------
// Mint - public auth (destination is public)
// ---------------------------------------------------------------------------

/// mint_to_public: destination is public -> public auth
#[test]
unconstrained fn mint_to_public_with_auth() {
    let (mut env, token, owner, _, minter, _) = setup_with_auth_and_minter();
    env.call_public(minter, Token::at(token).mint_to_public(owner, mint_amount));
    utils::check_public_balance(env, token, owner, mint_amount);
    utils::check_total_supply(env, token, mint_amount);
}

// ---------------------------------------------------------------------------
// Burn - private auth (source is private)
// ---------------------------------------------------------------------------

/// burn_private: source is private -> private auth
#[test]
unconstrained fn burn_private_with_auth() {
    let (mut env, token, owner, _, _) = setup_with_auth_and_private_balance();

    let burn_amount = mint_amount / (2 as u128);
    env.call_private(owner, Token::at(token).burn_private(owner, burn_amount, 0));

    utils::check_private_balance(env, token, owner, mint_amount - burn_amount);
    utils::check_total_supply(env, token, mint_amount - burn_amount);
}

// ---------------------------------------------------------------------------
// Burn - public auth (source is public)
// ---------------------------------------------------------------------------

/// burn_public: source is public -> public auth
#[test]
unconstrained fn burn_public_with_auth() {
    let (mut env, token, owner, _, _) = setup_with_auth_and_public_balance();

    let burn_amount = mint_amount / (2 as u128);
    env.call_public(owner, Token::at(token).burn_public(owner, burn_amount, 0));

    utils::check_public_balance(env, token, owner, mint_amount - burn_amount);
    utils::check_total_supply(env, token, mint_amount - burn_amount);
}

// ---------------------------------------------------------------------------
// Private-source transfers -> authorize_private (cross-contract private call)
// ---------------------------------------------------------------------------

/// transfer_private_to_private: source and destination both private -> private auth
#[test]
unconstrained fn transfer_private_to_private_with_auth() {
    let (mut env, token, owner, recipient, _) = setup_with_auth_and_private_balance();
    let transfer_amount = mint_amount / (10 as u128);

    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    env.call_private(
        owner,
        Token::at(token).transfer_private_to_private(owner, recipient, transfer_amount, 0),
    );

    utils::check_private_balance(env, token, owner, mint_amount - transfer_amount);
    utils::check_private_balance(env, token, recipient, transfer_amount);
}

/// transfer_private_to_public: source is private -> private auth
#[test]
unconstrained fn transfer_private_to_public_with_auth() {
    let (mut env, token, owner, recipient, _) = setup_with_auth_and_private_balance();
    let transfer_amount = mint_amount / (10 as u128);

    env.call_private(
        owner,
        Token::at(token).transfer_private_to_public(owner, recipient, transfer_amount, 0),
    );

    utils::check_private_balance(env, token, owner, mint_amount - transfer_amount);
    utils::check_public_balance(env, token, recipient, transfer_amount);
}

/// transfer_private_to_public_with_commitment: source is private -> private auth
#[test]
unconstrained fn transfer_private_to_public_with_commitment_with_auth() {
    let (mut env, token, owner, recipient, _) = setup_with_auth_and_private_balance();
    let transfer_amount = mint_amount / (10 as u128);

    let _commitment = env.call_private(
        owner,
        Token::at(token).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    utils::check_private_balance(env, token, owner, mint_amount - transfer_amount);
    utils::check_public_balance(env, token, recipient, transfer_amount);
}

/// transfer_private_to_commitment: source is private -> private auth
#[test]
unconstrained fn transfer_private_to_commitment_with_auth() {
    let (mut env, token, owner, recipient, _) = setup_with_auth_and_private_balance();
    let transfer_amount = mint_amount / (10 as u128);

    let commitment =
        env.call_private(owner, Token::at(token).initialize_transfer_commitment(recipient, owner));

    env.call_private(
        owner,
        Token::at(token).transfer_private_to_commitment(owner, commitment, transfer_amount, 0),
    );

    utils::check_private_balance(env, token, owner, mint_amount - transfer_amount);
    utils::check_private_balance(env, token, recipient, transfer_amount);
}

/// transfer_public_to_private: called in private context -> private auth (hides the transfer)
#[test]
unconstrained fn transfer_public_to_private_with_auth() {
    let (mut env, token, owner, recipient, _) = setup_with_auth_and_public_balance();
    let transfer_amount = mint_amount / (10 as u128);

    env.call_private(
        owner,
        Token::at(token).transfer_public_to_private(owner, recipient, transfer_amount, 0),
    );

    utils::check_public_balance(env, token, owner, mint_amount - transfer_amount);
    utils::check_private_balance(env, token, recipient, transfer_amount);
}

// ---------------------------------------------------------------------------
// Public-source transfers -> authorize_public (public context)
// ---------------------------------------------------------------------------

/// transfer_public_to_public: source is public -> public auth
#[test]
unconstrained fn transfer_public_to_public_with_auth() {
    let (mut env, token, owner, recipient, _) = setup_with_auth_and_public_balance();
    let transfer_amount = mint_amount / (10 as u128);

    env.call_public(
        owner,
        Token::at(token).transfer_public_to_public(owner, recipient, transfer_amount, 0),
    );

    utils::check_public_balance(env, token, owner, mint_amount - transfer_amount);
    utils::check_public_balance(env, token, recipient, transfer_amount);
}

/// transfer_public_to_commitment: source is public -> public auth
#[test]
unconstrained fn transfer_public_to_commitment_with_auth() {
    let (mut env, token, owner, recipient, _) = setup_with_auth_and_public_balance();
    let transfer_amount = mint_amount / (10 as u128);

    let commitment =
        env.call_private(owner, Token::at(token).initialize_transfer_commitment(recipient, owner));

    env.call_public(
        owner,
        Token::at(token).transfer_public_to_commitment(owner, commitment, transfer_amount, 0),
    );

    utils::check_public_balance(env, token, owner, mint_amount - transfer_amount);
    utils::check_private_balance(env, token, recipient, transfer_amount);
}
