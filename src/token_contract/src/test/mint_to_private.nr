use crate::{test::utils, Token};

#[test]
unconstrained fn mint_to_private_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let mint_amount: u128 = 10_000;
    env.call_private(
        minter,
        Token::at(token_contract_address).mint_to_private(owner, owner, mint_amount),
    );

    utils::check_private_balance(token_contract_address, owner, mint_amount);

    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    assert(total_supply == mint_amount);
}

#[test]
unconstrained fn mint_to_private_failures() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);

    // As non-minter
    let mint_amount: u128 = 10_000;
    let mint_to_private_call_interface =
        Token::at(token_contract_address).mint_to_private(owner, owner, mint_amount);
    // env.assert_private_call_fails(mint_to_private_call_interface);

    utils::check_private_balance(token_contract_address, owner, 0 as u128);

    // Overflow recipient

    // TODO: is there something like type(u128).max?
    let max_u128 = utils::max_u128();
    env.call_private(
        minter,
        Token::at(token_contract_address).mint_to_private(recipient, recipient, max_u128),
    );

    let mint_to_private_call_interface =
        Token::at(token_contract_address).mint_to_private(owner, owner, 1 as u128);
    // env.assert_private_call_fails(mint_to_private_call_interface);

    utils::check_private_balance(token_contract_address, owner, 0);
    utils::check_total_supply(token_contract_address, max_u128);

    // Overflow total supply
    let mint_to_private_call_interface =
        Token::at(token_contract_address).mint_to_private(owner, owner, mint_amount);
    // env.assert_private_call_fails(mint_to_private_call_interface);

    // utils::check_private_balance(token_contract_address, owner, 0);
}
