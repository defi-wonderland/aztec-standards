use crate::FPC;
use crate::test::utils;

/// Test scenario: Admin successfully withdraws accumulated funds.
/// Verifies that the admin can pull the entire token balance from the FPC to a specified recipient address.
#[test]
unconstrained fn test_admin_can_pull_accumulated_funds() {
    // Setup environment
    let (env, fpc_address, admin, user, token_address) = utils::setup();

    let token_amount = 1000;

    // Mint tokens to FPC
    utils::mint_to_public(env, token_address, admin, fpc_address, token_amount);
    // Verify FPC balance
    let fpc_balance = utils::public_token_balance(env, token_address, fpc_address);
    assert(fpc_balance == 1000);

    // Admin pulls funds
    env.impersonate(admin);
    FPC::at(fpc_address).pull_funds(user).call(&mut env.public());

    // Verify FPC balance is now 0
    let fpc_balance = utils::public_token_balance(env, token_address, fpc_address);
    assert(fpc_balance == 0);

    // Verify recipient balance
    let user_balance = utils::public_token_balance(env, token_address, user);
    assert(user_balance == 1000);
}

/// Test scenario: Admin attempts to pull funds when the contract balance is zero.
/// Verifies that the pull_funds function executes successfully even with a zero balance,
/// and that both the FPC and recipient balances remain zero.
#[test]
unconstrained fn test_admin_pull_funds_when_balance_is_zero() {
    // Setup environment
    let (env, fpc_address, admin, user, token_address) = utils::setup();

    // Verify FPC balance is 0
    let fpc_balance = utils::public_token_balance(env, token_address, fpc_address);
    assert(fpc_balance == 0);

    // Admin pulls funds (should be no-op)
    env.impersonate(admin);
    FPC::at(fpc_address).pull_funds(user).call(&mut env.public());

    // Verify FPC balance remains 0
    let fpc_balance = utils::public_token_balance(env, token_address, fpc_address);
    assert(fpc_balance == 0);

    // Verify recipient balance remains 0
    let user_balance = utils::public_token_balance(env, token_address, user);
    assert(user_balance == 0);
}

/// Test scenario: Non-admin attempts to pull funds.
/// Verifies that the call reverts with the specific error "Only admin can pull funds"
/// when initiated by an address other than the admin.
#[test(should_fail_with = "Only admin can pull funds")]
unconstrained fn test_non_admin_cannot_pull_funds() {
    // Setup environment
    let (env, fpc_address, _, user, _) = utils::setup();

    // Non-admin attempts to pull funds (should fail)
    env.impersonate(user);
    FPC::at(fpc_address).pull_funds(user).call(&mut env.public());
}
