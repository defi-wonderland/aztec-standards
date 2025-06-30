
use crate::{test::utils, Dripper};
use token::Token;

#[test]
unconstrained fn drip_to_public_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, dripper_contract_address, alice, bob) = utils::setup_dripper_and_token(false);

    // Note: In a real scenario, the dripper would need to be set as minter
    // For this test, we'll assume the dripper has minting permissions
    env.impersonate(alice);

    // Alice calls drip_to_public to mint tokens to herself
    env.impersonate(alice);
    let drip_amount = utils::drip_amount;
    Dripper::at(dripper_contract_address).drip_to_public(token_contract_address, drip_amount).call(&mut env.public());

    // Check that Alice received the tokens in her public balance
    utils::check_public_balance(token_contract_address, alice, drip_amount as u128);

    // Check that total supply increased
    utils::check_total_supply(token_contract_address, drip_amount as u128);

    // Check that Alice's private balance is still 0
    utils::check_private_balance(token_contract_address, alice, 0);
}

#[test]
unconstrained fn drip_to_public_multiple_users() {
    // Setup without account contracts
    let (env, token_contract_address, dripper_contract_address, alice, bob) = utils::setup_dripper_and_token(false);

    // Note: In a real scenario, the dripper would need to be set as minter
    // For this test, we'll assume the dripper has minting permissions
    env.impersonate(alice);

    let drip_amount = utils::drip_amount;

    // Alice drips tokens to herself
    env.impersonate(alice);
    Dripper::at(dripper_contract_address).drip_to_public(token_contract_address, drip_amount).call(&mut env.public());

    // Bob drips tokens to himself
    env.impersonate(bob);
    Dripper::at(dripper_contract_address).drip_to_public(token_contract_address, drip_amount).call(&mut env.public());

    // Check balances
    utils::check_public_balance(token_contract_address, alice, drip_amount as u128);
    utils::check_public_balance(token_contract_address, bob, drip_amount as u128);

    // Check total supply
    utils::check_total_supply(token_contract_address, (drip_amount * 2) as u128);
}

#[test]
unconstrained fn drip_to_public_large_amount() {
    // Setup without account contracts
    let (env, token_contract_address, dripper_contract_address, alice, bob) = utils::setup_dripper_and_token(false);

    // Note: In a real scenario, the dripper would need to be set as minter
    // For this test, we'll assume the dripper has minting permissions
    env.impersonate(alice);

    // Alice drips a large amount
    env.impersonate(alice);
    let large_amount: u64 = 1_000_000;
    Dripper::at(dripper_contract_address).drip_to_public(token_contract_address, large_amount).call(&mut env.public());

    // Check that Alice received the tokens
    utils::check_public_balance(token_contract_address, alice, large_amount as u128);
    utils::check_total_supply(token_contract_address, large_amount as u128);
}

