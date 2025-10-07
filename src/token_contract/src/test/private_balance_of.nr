use crate::test::utils::{check_private_balance, mint_amount, setup_with_minter};
use crate::Token;

#[test]
unconstrained fn direct_call_returns_correct_amount() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, _, minter) = setup_with_minter(false);

    env.call_private(minter, Token::at(token_contract_address).mint_to_private(owner, mint_amount));

    check_private_balance(env, token_contract_address, owner, mint_amount);

    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    assert(total_supply == mint_amount);

    let private_balance =
        env.call_private(owner, Token::at(token_contract_address).private_balance_of(owner));
    assert(private_balance == mint_amount);
}
