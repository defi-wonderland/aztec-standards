use crate::test::utils;
use crate::Token;
use authwit::cheatcodes as authwit_cheatcodes;
use uint_note::uint_note::UintNote;
use aztec::{
    note::constants::MAX_NOTES_PER_PAGE,
    oracle::random::random,
};

#[test]
unconstrained fn transfer_private_to_public_on_behalf_of_self() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, _, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ false);

    let transfer_private_to_public_amount = mint_amount / U128::from_integer(10);
    Token::at(token_contract_address)
        .transfer_private_to_public(owner, owner, transfer_private_to_public_amount, 0)
        .call(&mut env.private());
    utils::check_private_balance(
        token_contract_address,
        owner,
        mint_amount - transfer_private_to_public_amount,
    );
    utils::check_public_balance(
        token_contract_address,
        owner,
        transfer_private_to_public_amount,
    );
}

#[test]
unconstrained fn transfer_private_to_public_on_behalf_of_other() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ true);

    let transfer_private_to_public_amount = mint_amount / U128::from_integer(10);
    let transfer_private_to_public_call_interface = Token::at(token_contract_address)
        .transfer_private_to_public(owner, recipient, transfer_private_to_public_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_private_to_public_call_interface,
    );
    // Impersonate recipient
    env.impersonate(recipient);
    // transfer_private_to_public tokens
    transfer_private_to_public_call_interface.call(&mut env.private());
    utils::check_private_balance(
        token_contract_address,
        owner,
        mint_amount - transfer_private_to_public_amount,
    );
    utils::check_public_balance(
        token_contract_address,
        recipient,
        transfer_private_to_public_amount,
    );
}

#[test]
unconstrained fn transfer_private_to_public_multiple_notes_recursively() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, recipient) =
        utils::setup(/* with_account_contracts */ true);

    let notes_amount = U128::from_integer(1000);
    let notes_count = 12;
    let total_amount = notes_amount * U128::from_integer(notes_count);
    env.impersonate(owner);
    for i in 0..notes_count {
        utils::mint_to_private(env, token_contract_address, owner, notes_amount);
    }

    // Transfer tokens
    // Transfer will require 11 notes with change, which requires 2 recursive calls: 2 + 8 + 1
    let transfer_amount = total_amount - notes_amount - U128::from_integer(1);
    let transfer_private_from_call_interface = Token::at(token_contract_address)
        .transfer_private_to_public(owner, recipient, transfer_amount, 0);
    transfer_private_from_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    // Check that the notes still owned by the owner are correct
    env.impersonate(token_contract_address);
    let final_owner_notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        utils::get_private_balance_notes(owner, 0);
    assert(final_owner_notes.len() == 2, "Incorrect note count"); // 1000 UintNote x1 and 1 UintNote x1
    assert(final_owner_notes.get(0).get_value() == notes_amount, "Incorrect note amount");
    assert(
        final_owner_notes.get(1).get_value() == U128::from_integer(1),
        "Incorrect note change amount",
    );

    // Check that the notes generated to the recipient are correct
    env.impersonate(token_contract_address);
    let recipient_notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        utils::get_private_balance_notes(recipient, 0);
    assert(recipient_notes.len() == 0, "Incorrect transferred note count");

    // Check balances
    utils::check_private_balance(
        token_contract_address,
        owner,
        total_amount - transfer_amount,
    );
    utils::check_public_balance(
        token_contract_address,
        recipient,
        transfer_amount,
    );
}

#[test(should_fail)]
// TODO(#33): error logs don't match because of raw calls
// #[test(should_fail_with = "Balance too low")]
unconstrained fn transfer_private_to_public_failure_more_than_balance() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, _, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ false);

    let transfer_private_to_public_amount = mint_amount + U128::one();
    Token::at(token_contract_address)
        .transfer_private_to_public(owner, owner, transfer_private_to_public_amount, 0)
        .call(&mut env.private());
}

#[test(should_fail)]
// #[test(should_fail_with = "invalid nonce")]
unconstrained fn transfer_private_to_public_failure_on_behalf_of_self_non_zero_nonce() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, _, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ false);

    let transfer_private_to_public_amount = mint_amount + U128::one();
    Token::at(token_contract_address)
        .transfer_private_to_public(owner, owner, transfer_private_to_public_amount, random())
        .call(&mut env.private());
}

#[test(should_fail)]
// #[test(should_fail_with = "Balance too low")]
unconstrained fn transfer_private_to_public_failure_on_behalf_of_other_more_than_balance() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ true);

    let transfer_private_to_public_amount = mint_amount + U128::one();
    let transfer_private_to_public_call_interface = Token::at(token_contract_address)
        .transfer_private_to_public(owner, recipient, transfer_private_to_public_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_private_to_public_call_interface,
    );
    // Impersonate recipient
    env.impersonate(recipient);
    // transfer_private_to_public tokens
    transfer_private_to_public_call_interface.call(&mut env.private());
}

#[test(should_fail)]
// #[test(should_fail_with = "Authorization not found for message hash")]
unconstrained fn transfer_private_to_public_failure_on_behalf_of_other_invalid_designated_caller() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ true);

    let transfer_private_to_public_amount = mint_amount + U128::one();
    let transfer_private_to_public_call_interface = Token::at(token_contract_address)
        .transfer_private_to_public(owner, recipient, transfer_private_to_public_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        owner,
        transfer_private_to_public_call_interface,
    );
    // Impersonate recipient
    env.impersonate(recipient);
    // transfer_private_to_public tokens
    transfer_private_to_public_call_interface.call(&mut env.private());
}

#[test(should_fail)]
// #[test(should_fail_with = "Authorization not found for message hash")]
unconstrained fn transfer_private_to_public_failure_on_behalf_of_other_no_approval() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ true);

    let transfer_private_to_public_amount = mint_amount + U128::one();
    let transfer_private_to_public_call_interface = Token::at(token_contract_address)
        .transfer_private_to_public(owner, recipient, transfer_private_to_public_amount, 0);
    // Impersonate recipient
    env.impersonate(recipient);
    // transfer_private_to_public tokens
    transfer_private_to_public_call_interface.call(&mut env.private());
}
