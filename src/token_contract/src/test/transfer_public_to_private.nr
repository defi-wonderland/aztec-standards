use crate::{test::utils, Token};
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::oracle::random::random;
use std::test::OracleMock;
use uint_note::uint_note::{PartialUintNote, UintNote};

#[test]
unconstrained fn transfer_public_to_private_success() {
    let (env, token_contract_address, sender, recipient, mint_amount) =
        utils::setup_and_mint_to_public_without_minter(false);

    utils::check_public_balance(token_contract_address, sender, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, 0);

    let nonce = 0;
    let transfer_amount = mint_amount / 2;

    env.impersonate(sender);
    Token::at(token_contract_address)
        .transfer_public_to_private(sender, recipient, transfer_amount, nonce)
        .call(&mut env.private());
    env.advance_block_by(1);

    // sender public balance decreases
    utils::check_public_balance(token_contract_address, sender, transfer_amount);
    // recipient private balance incre ases
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
}

#[test(should_fail_with = "invalid nonce")]
unconstrained fn transfer_public_to_private_success_invalid_nonce() {
    let (env, token_contract_address, sender, recipient, mint_amount) =
        utils::setup_and_mint_to_public_without_minter(false);

    utils::check_public_balance(token_contract_address, sender, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, 0);

    let nonce = random();
    let transfer_amount = mint_amount / 2;

    env.impersonate(sender);
    Token::at(token_contract_address)
        .transfer_public_to_private(sender, recipient, transfer_amount, nonce)
        .call(&mut env.private());
}

#[test(should_fail_with = "Assertion failed: attempt to subtract with overflow 'public_balances.at(from).read() - amount'")]
unconstrained fn transfer_public_to_private_not_enough_balance() {
    let (env, token_contract_address, sender, recipient, mint_amount) =
        utils::setup_and_mint_to_public_without_minter(false);

    utils::check_public_balance(token_contract_address, sender, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, 0);

    let nonce = 0;
    let transfer_amount = mint_amount * 2;

    env.impersonate(sender);
    Token::at(token_contract_address)
        .transfer_public_to_private(sender, recipient, transfer_amount, nonce)
        .call(&mut env.private());
}

#[test]
unconstrained fn transfer_public_to_private_authwitness_success() {
    let (env, token_contract_address, sender, recipient, mint_amount) =
        utils::setup_and_mint_to_public_without_minter(true);

    let transfer_amount = mint_amount / 2;

    env.impersonate(sender);
    let transfer_public_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_private(sender, recipient, transfer_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        sender,
        recipient,
        transfer_public_to_private_call_interface,
    );

    env.impersonate(recipient);
    transfer_public_to_private_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    // Check balances changes as expected
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
    utils::check_public_balance(token_contract_address, sender, transfer_amount);
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn transfer_public_to_private_authwitness_unauthorized() {
    let (env, token_contract_address, sender, recipient, mint_amount) =
        utils::setup_and_mint_to_public_without_minter(true);

    let transfer_amount = mint_amount / 2;

    env.impersonate(sender);
    let transfer_public_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_private(sender, recipient, transfer_amount, 0);

    // no authwit added

    env.impersonate(recipient);
    transfer_public_to_private_call_interface.call(&mut env.private());
}
