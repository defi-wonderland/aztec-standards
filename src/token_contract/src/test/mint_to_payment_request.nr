use crate::{test::utils, Token};
use aztec::oracle::random::random;
use uint_note::uint_note::PartialUintNote;

#[test]
unconstrained fn mint_to_payment_request_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, _, recipient, minter) = utils::setup_with_minter(false);

    env.impersonate(minter);
    let payment_request = Token::at(token_contract_address)
        .initialize_payment_request(minter, recipient, minter)
        .call(&mut env.private());

    let mint_amount: u128 = 10_000;
    Token::at(token_contract_address).mint_to_payment_request(payment_request, mint_amount).call(
        &mut env.public(),
    );
    env.advance_block_by(1);

    utils::check_private_balance(token_contract_address, recipient, mint_amount);

    let total_supply = Token::at(token_contract_address).total_supply().view(&mut env.public());
    assert(total_supply == mint_amount);
}

#[test(should_fail_with = "caller is not minter")]
unconstrained fn mint_to_private_failure_unauthorized() {
    let (env, token_contract_address, _, recipient, _) = utils::setup_with_minter(false);

    env.impersonate(recipient);
    let payment_request = Token::at(token_contract_address)
        .initialize_payment_request(recipient, recipient, recipient)
        .call(&mut env.private());

    let mint_amount: u128 = 10_000;
    env.impersonate(recipient);
    let mint_to_payment_request_call_interface =
        Token::at(token_contract_address).mint_to_payment_request(payment_request, mint_amount);
    mint_to_payment_request_call_interface.call(&mut env.public());
}

#[test(should_fail_with = "attempt to add with overflow 'total_supply.read() + amount'")]
unconstrained fn mint_to_private_failure_balance_overflow() {
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);

    env.impersonate(minter);
    let payment_request = Token::at(token_contract_address)
        .initialize_payment_request(minter, recipient, minter)
        .call(&mut env.private());

    let max_u128 = utils::max_u128();
    Token::at(token_contract_address).mint_to_payment_request(payment_request, max_u128).call(
        &mut env.public(),
    );
    env.advance_block_by(1);

    let mint_to_payment_request_call_interface =
        Token::at(token_contract_address).mint_to_payment_request(payment_request, 2 as u128);
    mint_to_payment_request_call_interface.call(&mut env.public());
    // env.assert_private_call_fails(mint_to_private_call_interface);

    utils::check_private_balance(token_contract_address, owner, 0);
    utils::check_total_supply(token_contract_address, max_u128);
}

#[test(should_fail_with = "attempt to add with overflow 'total_supply.read() + amount'")]
unconstrained fn mint_to_private_failure_total_supply_overflow() {
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);

    env.impersonate(minter);
    let payment_request = Token::at(token_contract_address)
        .initialize_payment_request(minter, recipient, minter)
        .call(&mut env.private());

    let mint_amount: u128 = 10_000;
    let max_u128 = utils::max_u128();
    Token::at(token_contract_address).mint_to_payment_request(payment_request, max_u128).call(
        &mut env.public(),
    );

    utils::check_private_balance(token_contract_address, owner, 0);

    let another_payment_request = Token::at(token_contract_address)
        .initialize_payment_request(minter, recipient, minter)
        .call(&mut env.private());

    Token::at(token_contract_address)
        .mint_to_payment_request(another_payment_request, mint_amount)
        .call(&mut env.public());
}

#[test(should_fail_with = "Invalid partial note or completer 'context.nullifier_exists(validity_commitment, context.this_address())'")]
unconstrained fn mint_to_private_failure_invalid_payment_requests_random() {
    let (env, token_contract_address, _, _, minter) = utils::setup_with_minter(false);

    let mint_amount: u128 = 10_000;
    env.impersonate(minter);

    Token::at(token_contract_address).mint_to_payment_request(random(), mint_amount).call(
        &mut env.public(),
    );
}

#[test(should_fail_with = "Invalid partial note or completer 'context.nullifier_exists(validity_commitment, context.this_address())'")]
unconstrained fn mint_to_private_failure_invalid_payment_requests_zero() {
    let (env, token_contract_address, _, _, minter) = utils::setup_with_minter(false);

    let mint_amount: u128 = 10_000;
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_payment_request(0, mint_amount).call(&mut env.public());
}

#[test(should_fail_with = "Got 2 logs for tag")]
unconstrained fn mint_to_private_failure_already_completed_payment_request() {
    let (env, token_contract_address, _, recipient, minter) = utils::setup_with_minter(false);

    env.impersonate(minter);
    let payment_request = Token::at(token_contract_address)
        .initialize_payment_request(minter, recipient, minter)
        .call(&mut env.private());

    let mint_amount: u128 = 10_000;

    // mint to a payment request once
    Token::at(token_contract_address).mint_to_payment_request(payment_request, mint_amount).call(
        &mut env.public(),
    );
    env.advance_block_by(1);

    // balance should be minted
    utils::check_private_balance(token_contract_address, recipient, mint_amount);
    // balance should be equal to total supply
    utils::check_total_supply(token_contract_address, mint_amount);
    // mint to the same payment request again
    Token::at(token_contract_address).mint_to_payment_request(payment_request, mint_amount).call(
        &mut env.public(),
    );

    env.advance_block_by(1);

    // this will revert because the TXE will now notice that a tag has duplicate logs
    utils::check_private_balance(token_contract_address, recipient, mint_amount);
}
