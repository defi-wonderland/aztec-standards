use crate::FPC;
use crate::test::utils;
use aztec::oracle::random::random;

/// Test scenario: Successful public fee payment.
/// Verifies that a user with sufficient public balance can pay the fee via `fee_entrypoint_public`.
#[test]
unconstrained fn test_public_payment_success() {
    // Setup environment
    let (env, fpc_address, minter, user, token_address) = utils::setup();

    let nonce = unsafe { random() }; // Generate nonce
    let max_fee = 1000; // Fee amount

    // Mint initial balance to user
    utils::mint_to_public(env, token_address, minter, user, max_fee);

    // Prepare auth witness for the public transfer
    utils::prepare_public_transfer_authwit(token_address, user, fpc_address, max_fee, nonce);

    // Call the FPC public entrypoint as the user
    env.impersonate(user);
    FPC::at(fpc_address).fee_entrypoint_public(max_fee, nonce).call(&mut env.private());

    // Verify user balance decreased (by fee + gas estimate, hardcoded for now)
    // TODO: Calculate gas more accurately or remove hardcoded value
    let user_balance = utils::public_token_balance(env, token_address, user);
    assert(user_balance == 998);
}

/// Test scenario: Public fee payment failure due to insufficient balance.
/// Verifies that the call reverts with an overflow error when the user lacks sufficient public funds.
#[test(should_fail_with = "attempt to subtract with overflow 'public_balances.at(from).read() - amount'")]
unconstrained fn test_public_payment_fails_insufficient_user_balance() {
    // Setup environment
    let (env, fpc_address, minter, user, token_address) = utils::setup();

    let nonce = unsafe { random() }; // Generate nonce
    let max_fee = 1000; // Fee requested
    let user_initial_balance = 900; // User balance < max_fee

    // Mint insufficient balance to user
    utils::mint_to_public(env, token_address, minter, user, user_initial_balance);

    // Prepare auth witness
    utils::prepare_public_transfer_authwit(token_address, user, fpc_address, max_fee, nonce);

    // Call FPC public entrypoint (expected to fail)
    env.impersonate(user);
    FPC::at(fpc_address).fee_entrypoint_public(max_fee, nonce).call(&mut env.private());
}
