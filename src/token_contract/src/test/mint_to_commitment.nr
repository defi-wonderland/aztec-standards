use crate::{test::utils, Token};
use aztec::oracle::random::random;
use bignum_field::{bignum_field::BigNumField, bignum_field_note::BigNumFieldNote};
use bignum_field::bignum_field_note::PartialBigNumFieldNote;

#[test]
unconstrained fn mint_to_commitment_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);

    let commitment = Token::at(token_contract_address)
        .initialize_transfer_commitment(recipient, recipient)
        .call(&mut env.private());

    let mint_amount: BigNumField = BigNumField::new(10_000);
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_commitment(mint_amount, commitment).call(
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
    let commitment = Token::at(token_contract_address)
        .initialize_transfer_commitment(recipient, recipient)
        .call(&mut env.private());

    let mint_amount: BigNumField = BigNumField::new(10_000);
    env.impersonate(recipient);
    let mint_to_commitment_call_interface =
        Token::at(token_contract_address).mint_to_commitment(mint_amount, commitment);
    mint_to_commitment_call_interface.call(&mut env.public());
}

#[test(should_fail_with = "U256 addition overflow")]
unconstrained fn mint_to_private_failure_balance_overflow() {
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);

    env.impersonate(recipient);
    let commitment = Token::at(token_contract_address)
        .initialize_transfer_commitment(recipient, recipient)
        .call(&mut env.private());

    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_commitment(BigNumField::max(), commitment).call(
        &mut env.public(),
    );
    env.advance_block_by(1);

    let mint_to_commitment_call_interface =
        Token::at(token_contract_address).mint_to_commitment(BigNumField::new(2), commitment);
    mint_to_commitment_call_interface.call(&mut env.public());
}

#[test(should_fail_with = "U256 addition overflow")]
unconstrained fn mint_to_private_failure_total_supply_overflow() {
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);

    env.impersonate(recipient);
    let commitment = Token::at(token_contract_address)
        .initialize_transfer_commitment(recipient, recipient)
        .call(&mut env.private());

    let mint_amount: BigNumField = BigNumField::new(10_000);

    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_commitment(BigNumField::max(), commitment).call(
        &mut env.public(),
    );

    utils::check_private_balance(token_contract_address, owner, BigNumField::zero());

    let another_commitment = Token::at(token_contract_address)
        .initialize_transfer_commitment(recipient, recipient)
        .call(&mut env.private());

    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_commitment(mint_amount, another_commitment).call(
        &mut env.public(),
    );
}

#[test(should_fail_with = "Invalid commitment 'context.storage_read(commitment.commitment())'")]
unconstrained fn mint_to_private_failure_invalid_commitments_random() {
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);

    let mint_amount: BigNumField = BigNumField::new(10_000);
    env.impersonate(minter);

    Token::at(token_contract_address)
        .mint_to_commitment(mint_amount, PartialBigNumFieldNote { commitment: random() })
        .call(&mut env.public());
}

#[test(should_fail_with = "Invalid commitment 'context.storage_read(commitment.commitment())'")]
unconstrained fn mint_to_private_failure_invalid_commitments_zero() {
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);

    let mint_amount: BigNumField = BigNumField::new(10_000);
    env.impersonate(minter);
    Token::at(token_contract_address)
        .mint_to_commitment(mint_amount, PartialBigNumFieldNote { commitment: 0 })
        .call(&mut env.public());
}

#[test(should_fail_with = "Got 2 logs for tag")]
unconstrained fn mint_to_private_failure_already_completed_partial_note() {
    let (env, token_contract_address, _, recipient, minter) = utils::setup_with_minter(false);

    env.impersonate(recipient);
    let commitment = Token::at(token_contract_address)
        .initialize_transfer_commitment(recipient, recipient)
        .call(&mut env.private());

    let mint_amount: BigNumField = BigNumField::new(10_000);

    // mint to a commitment once
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_commitment(mint_amount, commitment).call(
        &mut env.public(),
    );
    env.advance_block_by(1);

    // balance should be minted
    utils::check_private_balance(token_contract_address, recipient, mint_amount);
    // balance should be equal to total supply
    utils::check_total_supply(token_contract_address, mint_amount);
    // mint to the same commitment again
    Token::at(token_contract_address).mint_to_commitment(mint_amount, commitment).call(
        &mut env.public(),
    );

    env.advance_block_by(1);

    // this will revert because the TXE will now notice that a tag has duplicate logs
    utils::check_private_balance(token_contract_address, recipient, mint_amount);
}
