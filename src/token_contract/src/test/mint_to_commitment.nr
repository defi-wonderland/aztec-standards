use crate::{test::utils, Token};
use aztec::oracle::random::random;

#[test]
unconstrained fn mint_to_commitment_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, _, recipient, minter) = utils::setup_with_minter(false);

    let commitment = env.call_private(
        minter,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, minter),
    );

    let mint_amount: u128 = 10_000;
    env.call_public(
        minter,
        Token::at(token_contract_address).mint_to_commitment(commitment, mint_amount),
    );

    utils::check_private_balance(env, token_contract_address, recipient, mint_amount);

    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    assert(total_supply == mint_amount);
}

#[test(should_fail_with = "caller is not minter")]
unconstrained fn mint_to_private_failure_unauthorized() {
    let (mut env, token_contract_address, _, recipient, _) = utils::setup_with_minter(false);

    let commitment = env.call_private(
        recipient,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, recipient),
    );

    let mint_amount: u128 = 10_000;
    env.call_public(
        recipient,
        Token::at(token_contract_address).mint_to_commitment(commitment, mint_amount),
    );
}

#[test(should_fail_with = "attempt to add with overflow 'self.storage.total_supply.read() + amount'")]
unconstrained fn mint_to_private_failure_balance_overflow() {
    let (mut env, token_contract_address, owner, recipient, minter) =
        utils::setup_with_minter(false);

    let commitment = env.call_private(
        minter,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, minter),
    );

    let max_u128 = utils::max_u128();
    env.call_public(
        minter,
        Token::at(token_contract_address).mint_to_commitment(commitment, max_u128),
    );

    env.call_public(
        minter,
        Token::at(token_contract_address).mint_to_commitment(commitment, 2 as u128),
    );
    // env.assert_private_call_fails(mint_to_private_call_interface);

    utils::check_private_balance(env, token_contract_address, owner, 0);
    utils::check_total_supply(env, token_contract_address, max_u128);
}

#[test(should_fail_with = "attempt to add with overflow 'self.storage.total_supply.read() + amount'")]
unconstrained fn mint_to_private_failure_total_supply_overflow() {
    let (mut env, token_contract_address, owner, recipient, minter) =
        utils::setup_with_minter(false);

    let commitment = env.call_private(
        minter,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, minter),
    );

    let mint_amount: u128 = 10_000;
    let max_u128 = utils::max_u128();
    env.call_public(
        minter,
        Token::at(token_contract_address).mint_to_commitment(commitment, max_u128),
    );

    utils::check_private_balance(env, token_contract_address, owner, 0);

    let another_commitment = env.call_private(
        minter,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, minter),
    );

    env.call_public(
        minter,
        Token::at(token_contract_address).mint_to_commitment(another_commitment, mint_amount),
    );
}

#[test(should_fail_with = "Invalid partial note or completer 'context.nullifier_exists_unsafe(validity_commitment, context.this_address())'")]
unconstrained fn mint_to_private_failure_invalid_commitments_random() {
    let (mut env, token_contract_address, _, _, minter) = utils::setup_with_minter(false);

    let mint_amount: u128 = 10_000;

    env.call_public(
        minter,
        Token::at(token_contract_address).mint_to_commitment(random(), mint_amount),
    );
}

#[test(should_fail_with = "Invalid partial note or completer 'context.nullifier_exists_unsafe(validity_commitment, context.this_address())'")]
unconstrained fn mint_to_private_failure_invalid_commitments_zero() {
    let (mut env, token_contract_address, _, _, minter) = utils::setup_with_minter(false);

    let mint_amount: u128 = 10_000;
    env.call_public(minter, Token::at(token_contract_address).mint_to_commitment(0, mint_amount));
}

#[test(should_fail_with = "Got 2 logs for tag")]
unconstrained fn mint_to_private_failure_already_completed_commitment() {
    let (mut env, token_contract_address, _, recipient, minter) = utils::setup_with_minter(false);

    let commitment = env.call_private(
        minter,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, minter),
    );

    let mint_amount: u128 = 10_000;

    // mint to a commitment once
    env.call_public(
        minter,
        Token::at(token_contract_address).mint_to_commitment(commitment, mint_amount),
    );

    // balance should be minted
    utils::check_private_balance(env, token_contract_address, recipient, mint_amount);
    // balance should be equal to total supply
    utils::check_total_supply(env, token_contract_address, mint_amount);
    // mint to the same commitment again
    env.call_public(
        minter,
        Token::at(token_contract_address).mint_to_commitment(commitment, mint_amount),
    );

    // this will revert because the TXE will now notice that a tag has duplicate logs
    utils::check_private_balance(env, token_contract_address, recipient, mint_amount);
}
