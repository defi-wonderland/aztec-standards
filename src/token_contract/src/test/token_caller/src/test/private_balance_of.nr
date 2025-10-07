use crate::test::utils::setup_with_minter;
use crate::TokenCaller;
use token::test::utils::{check_private_balance, mint_amount};
use token::Token;

#[test]
unconstrained fn indirect_call_returns_correct_amount() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, _, minter, token_caller_contract_address) =
        setup_with_minter(false);

    env.call_private(minter, Token::at(token_contract_address).mint_to_private(owner, mint_amount));

    check_private_balance(env, token_contract_address, owner, mint_amount);

    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    assert(total_supply == mint_amount);

    let private_balance = env.call_private(
        owner,
        TokenCaller::at(token_caller_contract_address).private_balance_of(token_contract_address),
    );
    assert(private_balance == mint_amount);
}
