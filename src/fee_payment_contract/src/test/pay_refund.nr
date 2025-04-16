use crate::FPC;
use crate::test::utils;

/// Test scenario: Successful fee payment and refund calculation via public entrypoint.
/// Verifies that when a user pays via `fee_entrypoint_public`, the correct `actual_fee`
/// is transferred to the FPC, and the remainder (`max_fee - actual_fee`) is implicitly
/// refunded (i.e., never leaves the user's account).
#[test]
unconstrained fn test_pay_refund_happy_path() {
    // Setup environment
    let (env, fpc_address, minter, user, token_address) = utils::setup();

    let max_fee = 1000; // Max fee user authorizes

    utils::mint_to_public(env, token_address, minter, fpc_address, max_fee);

    // NOTE: transaction fee is zero, so the full amount is refunded
    env.impersonate(fpc_address);
    FPC::at(fpc_address).pay_refund_internal(user, max_fee, token_address).call(&mut env.public());

    let final_user_balance = utils::public_token_balance(env, token_address, user);
    let final_fpc_balance = utils::public_token_balance(env, token_address, fpc_address);

    assert(final_user_balance == 1000);
    assert(final_fpc_balance == 0);
}
