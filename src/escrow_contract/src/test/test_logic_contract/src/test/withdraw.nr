use crate::test::utils as logic_utils;
use crate::TestLogic;
use token::{test::utils as token_utils, Token};

// TODO: add test for successful withdraws via the logic contract. Currently it is not possible
// because the address cannot be set in the salt nor we cannot modify the logic address to be the salt

#[test(should_fail_with = "Not Authorized")]
unconstrained fn withdraw_unauthorized() {
    let (mut env, escrow, token, _, _, recipient, minter) =
        logic_utils::set_escrow_with_token_and_nft(false, 1);

    // Mint some tokens to escrow
    let amount: u128 = token_utils::mint_amount;
    env.call_private(minter, Token::at(token).mint_to_private(escrow, amount));

    // Check the escrow received and can read the tokens
    token_utils::check_private_balance(env, token, escrow, amount);

    let logic = logic_utils::deploy_logic(&mut env, 1);

    let caller = env.create_light_account();
    env.call_private(caller, TestLogic::at(logic).withdraw(escrow, recipient, token, amount));
}
