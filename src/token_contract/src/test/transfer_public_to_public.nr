use crate::test::utils::{self, mint_amount};
use crate::Token;
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test]
unconstrained fn public_transfer() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);
    // Transfer tokens
    let transfer_amount = mint_amount / (10 as u128);
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_public(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    // Check balances
    utils::check_public_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_public_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn public_transfer_to_self() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, _) =
        utils::setup_and_mint_to_public_without_minter(false);
    // Transfer tokens
    let transfer_amount = mint_amount / (10 as u128);
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_public(
            owner,
            owner,
            transfer_amount,
            0,
        ),
    );
    // Check balances
    utils::check_public_balance(env, token_contract_address, owner, mint_amount);
}

#[test]
unconstrained fn public_transfer_on_behalf_of_other() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);
    let transfer_amount = mint_amount / (10 as u128);
    let public_transfer_private_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount, 1);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        env,
        owner,
        recipient,
        public_transfer_private_to_private_call_interface,
    );
    // Impersonate recipient to perform the call
    // Transfer tokens
    env.call_public(recipient, public_transfer_private_to_private_call_interface);
    // Check balances
    utils::check_public_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_public_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test(should_fail_with = "attempt to subtract with overflow 'public_balances.at(from).read() - amount'")]
unconstrained fn public_transfer_failure_more_than_balance() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);
    // Transfer tokens
    let transfer_amount = mint_amount + (1 as u128);
    let public_transfer_call_interface = Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount, 0);
    // Try to transfer tokens
    env.call_public(owner, public_transfer_call_interface);
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn public_transfer_failure_on_behalf_of_other_without_approval() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);
    let transfer_amount = mint_amount / (10 as u128);
    let public_transfer_private_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount, 1);
    // Impersonate recipient to perform the call
    // Try to transfer tokens
    env.call_public(recipient, public_transfer_private_to_private_call_interface);
}

#[test(should_fail_with = "attempt to subtract with overflow 'public_balances.at(from).read() - amount'")]
unconstrained fn public_transfer_failure_on_behalf_of_other_more_than_balance() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);
    let transfer_amount = mint_amount + (1 as u128);
    let public_transfer_private_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount, 1);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        env,
        owner,
        recipient,
        public_transfer_private_to_private_call_interface,
    );
    // Impersonate recipient to perform the call
    // Try to transfer tokens
    env.call_public(recipient, public_transfer_private_to_private_call_interface);
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn public_transfer_failure_on_behalf_of_other_wrong_caller() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);
    let transfer_amount = mint_amount / (10 as u128);
    let public_transfer_private_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount, 1);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        env,
        owner,
        owner,
        public_transfer_private_to_private_call_interface,
    );
    // Impersonate recipient to perform the call
    // Try to transfer tokens
    env.call_public(recipient, public_transfer_private_to_private_call_interface);
}
