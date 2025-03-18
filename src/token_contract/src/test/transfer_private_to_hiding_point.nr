use crate::test::utils;
use crate::Token;
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::oracle::random::random;

#[test]
unconstrained fn transfer_private_to_hiding_point() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private_without_minter(/* with_account_contracts */ false);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, U128::from_integer(0));

    // Prepare hiding point slot
    env.impersonate(recipient);
    let hiding_point_slot: Field = Token::at(token_contract_address)
        .prepare_transfer_public_to_private(recipient, recipient)
        .call(&mut env.private());

    // Transfer tokens
    let transfer_amount = mint_amount;
    env.impersonate(owner);
    Token::at(token_contract_address)
        .transfer_private_to_hiding_point(owner, transfer_amount, hiding_point_slot, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check balances
    utils::check_private_balance(token_contract_address, owner, U128::from_integer(0));
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn transfer_private_to_hiding_point_on_behalf_of_other() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private_without_minter(/* with_account_contracts */ true);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, U128::from_integer(0));

    let transfer_amount = mint_amount;

    // Prepare hiding point slot
    env.impersonate(recipient);
    let hiding_point_slot: Field = Token::at(token_contract_address)
        .prepare_transfer_public_to_private(recipient, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    let transfer_to_hiding_point_call_interface = Token::at(token_contract_address)
        .transfer_private_to_hiding_point(owner, transfer_amount, hiding_point_slot, 0);

    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_to_hiding_point_call_interface,
    );

    // Transfer tokens
    env.impersonate(recipient);
    transfer_to_hiding_point_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    // Check balances
    utils::check_private_balance(token_contract_address, owner, U128::from_integer(0));
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
}

#[test(should_fail_with = "invalid nonce")]
unconstrained fn transfer_private_to_hiding_point_non_zero_nonce() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private_without_minter(/* with_account_contracts */ false);

    // Prepare hiding point slot
    env.impersonate(recipient);
    let hiding_point_slot: Field = Token::at(token_contract_address)
        .prepare_transfer_public_to_private(recipient, recipient)
        .call(&mut env.private());

    // Transfer tokens
    let transfer_amount = mint_amount;
    env.impersonate(owner);
    Token::at(token_contract_address)
        .transfer_private_to_hiding_point(owner, transfer_amount, hiding_point_slot, random())
        .call(&mut env.private());
}
