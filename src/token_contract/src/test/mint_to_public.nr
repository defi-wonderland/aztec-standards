use crate::{test::utils, Token};

#[test]
unconstrained fn mint_to_public_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let token = Token::at(token_contract_address);

    let mint_amount: u128 = 10_000;
    env.call_public(minter, token.mint_to_public(owner, mint_amount));

    utils::check_public_balance(env, token_contract_address, owner, mint_amount);

    let total_supply = env.view_public(token.total_supply());
    assert(total_supply == mint_amount);
}

#[test(should_fail_with = "Contract execution has reverted: Assertion failed: caller is not minter 'minter.eq(sender)'")]
unconstrained fn mint_to_public_failure_as_non_minter() {
    let (mut env, token_contract_address, owner, recipient, _) = utils::setup_with_minter(false);

    let mint_amount: u128 = 10_000;
    let mint_to_public_call_interface =
        Token::at(token_contract_address).mint_to_public(owner, mint_amount);

    // As non-minter
    env.call_public(recipient, mint_to_public_call_interface);
}

#[test(should_fail_with = "Contract execution has reverted: Assertion failed: attempt to add with overflow 'public_balances.at(to).read() + amount'")]
unconstrained fn mint_to_public_failure_recipient_balance_overflow() {
    let (mut env, token_contract_address, owner, recipient, minter) =
        utils::setup_with_minter(false);

    // We have to do this in 2 steps because we have to pass in a valid u128
    let max_u128 = utils::max_u128();
    env.call_public(minter, Token::at(token_contract_address).mint_to_public(recipient, max_u128));

    utils::check_public_balance(env, token_contract_address, owner, 0);
    utils::check_total_supply(env, token_contract_address, max_u128);

    // Overflow recipient's balance
    env.call_public(minter, Token::at(token_contract_address).mint_to_public(recipient, 1 as u128));
}

#[test(should_fail_with = "Contract execution has reverted: Assertion failed: attempt to add with overflow 'public_balances.at(to).read() + amount'")]
unconstrained fn mint_to_public_failure_overflow_total_supply() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let max_u128 = utils::max_u128();
    let mint_to_public_call_interface =
        Token::at(token_contract_address).mint_to_public(owner, max_u128);

    env.call_public(minter, mint_to_public_call_interface);
    utils::check_public_balance(env, token_contract_address, owner, max_u128);

    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    assert(total_supply == max_u128);

    // Overflow total supply
    env.call_public(minter, Token::at(token_contract_address).mint_to_public(owner, 1 as u128));
}
