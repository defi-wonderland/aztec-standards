use crate::{test::utils, Token};
use aztec::oracle::random::random;
use uint_note::uint_note::PartialUintNote;

#[test]
unconstrained fn test_mint_to_commitment() {
    // Setup once
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);

    // Calculate max u128 for overflow tests
    let two_pow_127 = 2.pow_32(127);
    let two_pow_127_minus_one = two_pow_127 - 1;
    let max_u128 = (two_pow_127 + two_pow_127_minus_one) as u128;

    env.impersonate(minter);
    let commitment = Token::at(token_contract_address)
        .initialize_transfer_commitment(minter, recipient, minter)
        .call(&mut env.private());
    env.advance_block_by(1);

    let mint_amount: u128 = 10_000;

    // Failure case 1: Unauthorized minter
    // "caller is not minter"
    env.impersonate(recipient);
    let mint_to_commitment_call =
        Token::at(token_contract_address).mint_to_commitment(commitment, mint_amount);
    env.assert_public_call_fails(mint_to_commitment_call);

    // Success case: Mint to commitment
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_commitment(commitment, mint_amount).call(
        &mut env.public(),
    );
    env.advance_block_by(1);

    utils::check_private_balance(token_contract_address, recipient, mint_amount);
    let total_supply = Token::at(token_contract_address).total_supply().view(&mut env.public());
    assert(total_supply == mint_amount);

    // Failure case 2: Mint to an already completed commitment
    // "Got 2 logs for tag"
    let duplicate_mint_call =
        Token::at(token_contract_address).mint_to_commitment(commitment, mint_amount);
    env.assert_public_call_fails(duplicate_mint_call);

    // Failure case 3: Balance overflow - mint max then try to mint more
    // "attempt to add with overflow 'total_supply.read() + amount'"
    env.impersonate(minter);
    let commitment_3 = Token::at(token_contract_address)
        .initialize_transfer_commitment(minter, recipient, minter)
        .call(&mut env.private());
    env.advance_block_by(1);

    // First mint max_u128 - mint_amount to leave room for our initial mint
    Token::at(token_contract_address).mint_to_commitment(commitment_3, max_u128 - mint_amount).call(
        &mut env.public(),
    );
    env.advance_block_by(1);

    // Now try to mint more which should overflow
    let commitment_4 = Token::at(token_contract_address)
        .initialize_transfer_commitment(minter, recipient, minter)
        .call(&mut env.private());
    env.advance_block_by(1);

    let overflow_mint_call =
        Token::at(token_contract_address).mint_to_commitment(commitment_4, 2 as u128);
    env.assert_public_call_fails(overflow_mint_call);

    utils::check_private_balance(token_contract_address, owner, 0);
    utils::check_total_supply(token_contract_address, max_u128);

    // Failure case 4: Invalid commitment - random value
    // "Invalid partial note or completer 'context.nullifier_exists(validity_commitment, context.this_address())'"
    env.impersonate(minter);
    let invalid_mint_call_1 =
        Token::at(token_contract_address).mint_to_commitment(random(), mint_amount);
    env.assert_public_call_fails(invalid_mint_call_1);

    // Failure case 5: Invalid commitment - zero
    // "Invalid partial note or completer 'context.nullifier_exists(validity_commitment, context.this_address())'"
    let invalid_mint_call_2 = Token::at(token_contract_address).mint_to_commitment(0, mint_amount);
    env.assert_public_call_fails(invalid_mint_call_2);
}
