use crate::FPC;
use crate::test::utils;
use aztec::oracle::random::random;

#[test]
unconstrained fn test_private_payment_success() {
    let (env, fpc_address, minter, user, token_address) = utils::setup();

    let nonce = unsafe { random() };
    let note_randomness = unsafe { random() };
    let max_fee = 1000;

    utils::mint_to_private(env, token_address, minter, user, max_fee);
    utils::check_private_balance(token_address, user, max_fee);

    utils::add_token_note(env, token_address, user, max_fee, note_randomness);
    utils::check_private_balance(token_address, user, max_fee);

    utils::prepare_private_transfer_authwit(token_address, user, fpc_address, max_fee, nonce);

    env.impersonate(user);
    FPC::at(fpc_address).fee_entrypoint_private(max_fee, nonce).call(&mut env.private());
}

unconstrained fn test_private_payment_fails_insufficient_balance() {}
