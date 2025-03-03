use crate::test::utils;
use crate::Token;
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::oracle::debug_log::debug_log;

#[test]
unconstrained fn transfer_private_to_public_with_hiding_point() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ false);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, U128::from_integer(0));

    // Prepare hiding point slot
    env.impersonate(recipient);
    let hiding_point_slot: Field = Token::at(token_contract_address)
        .prepare_transfer_public_to_private(recipient, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Transfer tokens
    let transfer_amount = mint_amount;
    env.impersonate(owner);
    let hiding_point_slot = Token::at(token_contract_address)
        .transfer_private_to_public_with_hiding_point(owner, recipient, transfer_amount, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check balances
    utils::check_private_balance(token_contract_address, owner, U128::from_integer(0));
    utils::check_public_balance(token_contract_address, recipient, transfer_amount);
}

// #[test]
unconstrained fn transfer_private_to_public_with_hiding_point_on_behalf_of_other() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ true);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, U128::from_integer(0));

    // Transfer tokens
    let transfer_amount = mint_amount;

    let transfer_private_to_public_hiding_point_call_interface = Token::at(token_contract_address)
        .transfer_private_to_public_with_hiding_point(owner, recipient, transfer_amount, 0);

    // TODO: Unable to compile if non-void call interface is used
    // authwit_cheatcodes::add_private_authwit_from_call_interface(
    //     owner,
    //     recipient,
    //     transfer_private_to_public_hiding_point_call_interface,
    // );

    // Transfer tokens
    env.impersonate(recipient);
    transfer_private_to_public_hiding_point_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    // Check balances
    utils::check_private_balance(token_contract_address, owner, U128::from_integer(0));
    utils::check_public_balance(token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn transfer_private_to_public_with_hiding_point_and_finalize() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ false);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, U128::from_integer(0));

    // Transfer tokens
    let transfer_amount = mint_amount;

    env.impersonate(owner);
    let hiding_point_slot = Token::at(token_contract_address)
        .transfer_private_to_public_with_hiding_point(owner, recipient, transfer_amount, 0)
        .call(&mut env.private());

    // Before finalize the recipient should have the tokens in public balance
    utils::check_public_balance(token_contract_address, recipient, transfer_amount);

    // Transfer tokens
    env.impersonate(recipient);
    Token::at(token_contract_address)
        .finalize_transfer_public_to_private(recipient, transfer_amount, hiding_point_slot, 0)
        .call(&mut env.public());
    env.advance_block_by(1);

    // Check balances
    utils::check_private_balance(token_contract_address, owner, U128::from_integer(0));
    utils::check_public_balance(token_contract_address, recipient, U128::from_integer(0));
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
}

#[test(should_fail)]
unconstrained fn transfer_private_to_public_with_hiding_point_and_finalize_with_invalid_hiding_point() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ false);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, U128::from_integer(0));

    // Transfer tokens
    let transfer_amount = mint_amount;

    env.impersonate(owner);
    let hiding_point_slot = Token::at(token_contract_address)
        .transfer_private_to_public_with_hiding_point(owner, recipient, transfer_amount, 0)
        .call(&mut env.private());

    let invalid_hiding_point = 1337;

    // Transfer tokens
    env.impersonate(recipient);
    Token::at(token_contract_address)
        .finalize_transfer_public_to_private(recipient, transfer_amount, invalid_hiding_point, 0)
        .call(&mut env.public());
}

// This test is passing although we pass `0` as `hiding_point_slot`
#[test]
unconstrained fn transfer_private_to_public_with_hiding_point_and_finalize_with_invalid_hiding_point_literals() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ false);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, U128::from_integer(0));

    // Transfer tokens
    let transfer_amount = mint_amount;

    env.impersonate(owner);
    let hiding_point_slot = Token::at(token_contract_address)
        .transfer_private_to_public_with_hiding_point(owner, recipient, transfer_amount, 0)
        .call(&mut env.private());

    // Transfer tokens
    env.impersonate(recipient);
    Token::at(token_contract_address)
        .finalize_transfer_public_to_private(recipient, transfer_amount, 0, 0)
        .call(&mut env.public());
}
