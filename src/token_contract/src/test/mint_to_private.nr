use crate::{test::utils, Token};

#[test]
unconstrained fn mint_to_private_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let mint_amount: u128 = 10_000;
    env.call_private(minter, Token::at(token_contract_address).mint_to_private(owner, mint_amount));

    utils::check_private_balance(env, token_contract_address, owner, mint_amount);

    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    assert(total_supply == mint_amount);
}

#[test(should_fail_with = "Assertion failed: caller is not minter")]
unconstrained fn mint_to_private_failure_as_non_minter() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, recipient, _) = utils::setup_with_minter(false);

    let mint_amount: u128 = 10_000;
    let mint_to_private_call_interface =
        Token::at(token_contract_address).mint_to_private(owner, mint_amount);
    // As non-minter
    env.call_private(recipient, mint_to_private_call_interface);
}

#[test(should_fail_with = "Contract execution has reverted: Assertion failed: attempt to add with overflow 'total_supply.read() + amount'")]
unconstrained fn mint_to_private_failure_recipient_balance_overflow() {
    let (mut env, token_contract_address, owner, recipient, minter) =
        utils::setup_with_minter(false);
    env.call_private(
        minter,
        Token::at(token_contract_address).mint_to_private(recipient, utils::max_u128()),
    );

    // Recipient's balance overflows
    env.call_private(minter, Token::at(token_contract_address).mint_to_private(owner, 1 as u128));
}
#[test(should_fail_with = "Contract execution has reverted: Assertion failed: attempt to add with overflow 'total_supply.read() + amount'")]
unconstrained fn mint_to_private_failure_total_supply_overflow() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, recipient, minter) =
        utils::setup_with_minter(false);

    env.call_private(
        minter,
        Token::at(token_contract_address).mint_to_private(recipient, utils::max_u128()),
    );
    env.call_private(minter, Token::at(token_contract_address).mint_to_private(owner, 1 as u128));
}
