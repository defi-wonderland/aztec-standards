use crate::{test::utils, Token};
use uint253::{uint253::U253, uint253_note::U253Note};

#[test]
unconstrained fn mint_to_public_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, _, minter) =
        utils::setup_with_minter(/* with_account_contracts */ false);

    env.impersonate(minter);
    let mint_amount: U253 = U253::new(10_000);
    Token::at(token_contract_address).mint_to_public(owner, mint_amount).call(&mut env.public());

    utils::check_public_balance(token_contract_address, owner, mint_amount);

    let total_supply = Token::at(token_contract_address).total_supply().view(&mut env.public());
    assert(total_supply == mint_amount);
}

#[test]
unconstrained fn mint_to_public_failures() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, recipient, minter) =
        utils::setup_with_minter(/* with_account_contracts */ false);

    // As non-minter
    let mint_amount: U253 = U253::new(10_000);
    env.impersonate(recipient);
    let mint_to_public_call_interface =
        Token::at(token_contract_address).mint_to_public(owner, mint_amount);
    env.assert_public_call_fails(mint_to_public_call_interface);

    utils::check_public_balance(token_contract_address, owner, U253::zero());

    env.impersonate(minter);

    // Overflow recipient

    // We have to do this in 2 steps because we have to pass in a valid U253
    let max_U253 = U253::max();
    Token::at(token_contract_address).mint_to_public(recipient, max_U253).call(&mut env.public());

    let mint_to_public_call_interface =
        Token::at(token_contract_address).mint_to_public(owner, U253::one());
    env.assert_public_call_fails(mint_to_public_call_interface);

    utils::check_public_balance(token_contract_address, owner, U253::zero());
    utils::check_total_supply(token_contract_address, max_U253);

    // Overflow total supply
    let mint_to_public_call_interface =
        Token::at(token_contract_address).mint_to_public(owner, max_U253);
    env.assert_public_call_fails(mint_to_public_call_interface);

    utils::check_public_balance(token_contract_address, owner, U253::zero());
}
