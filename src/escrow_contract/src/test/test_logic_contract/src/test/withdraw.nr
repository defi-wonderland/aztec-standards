use crate::test::utils as logic_utils;
use crate::TestLogic;
use token::{test::utils as token_utils, Token};

// TODO: add test for successful withdraws via the logic contract. Currently it is not possible
// because the address cannot be set in the salt nor we cannot modify the logic address to be the salt

#[test(should_fail_with = "Not Authorized")]
unconstrained fn withdraw_unauthorized() {
    let (env, escrow, token, _, _, recipient, minter) =
        logic_utils::set_escrow_with_token_and_nft(false, 1);

    // Mint some tokens to escrow
    let amount: u128 = token_utils::mint_amount;
    env.impersonate(minter);
    Token::at(token).mint_to_private(minter, escrow, amount).call(&mut env.private());
    env.advance_block_by(1);

    // Check the escrow received and can read the tokens
    token_utils::check_private_balance(token, escrow, amount);

    let logic = logic_utils::deploy_logic(env, 1);

    TestLogic::at(logic).withdraw(escrow, token, recipient, amount).call(&mut env.private());
}
