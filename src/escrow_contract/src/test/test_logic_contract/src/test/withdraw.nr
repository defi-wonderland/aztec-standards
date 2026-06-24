use crate::test::utils as logic_utils;
use crate::TestLogic;
use aztec::test::helpers::test_environment::CallPrivateOptions;
use escrow_contract::test::utils as escrow_utils;
use token::{test::utils as token_utils, Token};

#[test]
unconstrained fn withdraw_success() {
    let (mut env, token, _owner, recipient, minter) = token_utils::setup_with_minter(false);

    let escrow_class_id = escrow_utils::get_escrow_class_id();
    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);
    let escrow = escrow_utils::deploy_escrow_with_secret(&mut env, 1, logic);

    // Mint some tokens to escrow
    let amount: u128 = token_utils::mint_amount;
    env.call_private(minter, Token::at(token).mint_to_private(escrow, amount));

    // Check the escrow received and can read the tokens
    token_utils::check_private_balance(env, token, escrow, amount);

    let caller = env.create_light_account();
    env.call_private_opts(
        caller,
        CallPrivateOptions::new().with_additional_scopes([escrow]),
        TestLogic::at(logic).withdraw(escrow, recipient, token, amount),
    );

    // Check recipient got tokens
    token_utils::check_private_balance(env, token, recipient, amount);
}

#[test(should_fail_with = "Not Authorized")]
unconstrained fn withdraw_unauthorized() {
    let (mut env, escrow, token, _, _, recipient, minter, _) =
        escrow_utils::set_escrow_with_token_and_nft(false, 1);

    // Mint some tokens to escrow
    let amount: u128 = token_utils::mint_amount;
    env.call_private(minter, Token::at(token).mint_to_private(escrow, amount));

    // Check the escrow received and can read the tokens
    token_utils::check_private_balance(env, token, escrow, amount);

    let logic = logic_utils::deploy_logic(&mut env, 1);

    let caller = env.create_light_account();
    env.call_private(caller, TestLogic::at(logic).withdraw(escrow, recipient, token, amount));
}
