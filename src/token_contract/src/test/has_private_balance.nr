use crate::test::utils::{check_private_balance, mint_amount, setup_with_minter};
use crate::Token;

#[test]
unconstrained fn direct_call_exact_target_returns_true() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, _, minter) = setup_with_minter(false);

    env.call_private(minter, Token::at(token_contract_address).mint_to_private(owner, mint_amount));

    check_private_balance(env, token_contract_address, owner, mint_amount);

    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    assert(total_supply == mint_amount);

    let mut has_private_balance: bool = false;
    let has_private_balance = env.call_private(
        owner,
        Token::at(token_contract_address).has_private_balance(owner, mint_amount),
    );
    assert(has_private_balance == true);
}

#[test]
unconstrained fn direct_call_below_target_returns_true() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, _, minter) = setup_with_minter(false);

    env.call_private(minter, Token::at(token_contract_address).mint_to_private(owner, mint_amount));

    check_private_balance(env, token_contract_address, owner, mint_amount);

    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    assert(total_supply == mint_amount);

    let mut has_private_balance: bool = false;
    let has_private_balance = env.call_private(
        owner,
        Token::at(token_contract_address).has_private_balance(owner, mint_amount - 1),
    );
    assert(has_private_balance == true);
}

#[test]
unconstrained fn direct_call_above_target_returns_false() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, _, minter) = setup_with_minter(false);

    env.call_private(minter, Token::at(token_contract_address).mint_to_private(owner, mint_amount));

    check_private_balance(env, token_contract_address, owner, mint_amount);

    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    assert(total_supply == mint_amount);

    let mut has_private_balance: bool = true;
    let has_private_balance = env.call_private(
        owner,
        Token::at(token_contract_address).has_private_balance(owner, mint_amount + 1),
    );
    assert(has_private_balance == false);
}
