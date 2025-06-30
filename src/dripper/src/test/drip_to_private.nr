

use crate::{test::utils, Dripper};
use token::Token;
use aztec::oracle::random::random;
use std::test::OracleMock;

#[test]
unconstrained fn drip_to_private_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, dripper_contract_address, alice, bob) = utils::setup_dripper_and_token(false);

    // Note: In a real scenario, the dripper would need to be set as minter
    // For this test, we'll assume the dripper has minting permissions
    env.impersonate(alice);

    // Mock randomness for private note creation
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    // Alice calls drip_to_private to mint tokens to herself
    env.impersonate(alice);
    let drip_amount = utils::drip_amount;
    Dripper::at(dripper_contract_address).drip_to_private(token_contract_address, drip_amount).call(&mut env.private());

    env.advance_block_by(1);

    // Check that Alice received the tokens in her private balance
    utils::check_private_balance(token_contract_address, alice, drip_amount as u128);

    // Check that total supply increased
    utils::check_total_supply(token_contract_address, drip_amount as u128);

    // Check that Alice's public balance is still 0
    utils::check_public_balance(token_contract_address, alice, 0);
}

#[test]
unconstrained fn drip_to_private_multiple_users() {
    // Setup without account contracts
    let (env, token_contract_address, dripper_contract_address, alice, bob) = utils::setup_dripper_and_token(false);

    // Note: In a real scenario, the dripper would need to be set as minter
    // For this test, we'll assume the dripper has minting permissions
    env.impersonate(alice);

    let drip_amount = utils::drip_amount;

    // Mock randomness for private note creation
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    // Alice drips tokens to herself privately
    env.impersonate(alice);
    Dripper::at(dripper_contract_address).drip_to_private(token_contract_address, drip_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Bob drips tokens to himself privately
    env.impersonate(bob);
    Dripper::at(dripper_contract_address).drip_to_private(token_contract_address, drip_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Check private balances
    utils::check_private_balance(token_contract_address, alice, drip_amount as u128);
    utils::check_private_balance(token_contract_address, bob, drip_amount as u128);

    // Check total supply
    utils::check_total_supply(token_contract_address, (drip_amount * 2) as u128);

    // Check public balances are still 0
    utils::check_public_balance(token_contract_address, alice, 0);
    utils::check_public_balance(token_contract_address, bob, 0);
}

#[test]
unconstrained fn drip_to_private_large_amount() {
    // Setup without account contracts
    let (env, token_contract_address, dripper_contract_address, alice, bob) = utils::setup_dripper_and_token(false);

    // Note: In a real scenario, the dripper would need to be set as minter
    // For this test, we'll assume the dripper has minting permissions
    env.impersonate(alice);

    // Mock randomness for private note creation
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    // Alice drips a large amount privately
    env.impersonate(alice);
    let large_amount: u64 = 1_000_000;
    Dripper::at(dripper_contract_address).drip_to_private(token_contract_address, large_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Check that Alice received the tokens privately
    utils::check_private_balance(token_contract_address, alice, large_amount as u128);
    utils::check_total_supply(token_contract_address, large_amount as u128);
    utils::check_public_balance(token_contract_address, alice, 0);
}


