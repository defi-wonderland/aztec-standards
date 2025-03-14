use crate::test::utils;
use crate::Token;
use authwit::cheatcodes as authwit_cheatcodes;
use uint_note::uint_note::UintNote;
use aztec::note::constants::MAX_NOTES_PER_PAGE;

#[test]
unconstrained fn transfer_private_on_behalf_of_other() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ true);
    // Add authwit
    let transfer_amount = U128::from_integer(1000);
    let transfer_private_from_call_interface = Token::at(token_contract_address)
        .transfer_private_to_private(owner, recipient, transfer_amount, 1);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_private_from_call_interface,
    );
    // Impersonate recipient to perform the call
    env.impersonate(recipient);
    // Transfer tokens
    transfer_private_from_call_interface.call(&mut env.private());
    // Check balances
    utils::check_private_balance(token_contract_address, owner, mint_amount - transfer_amount);
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn transfer_private_multiple_notes_recursively() {
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
        .transfer_private_to_private(owner, recipient, transfer_amount, 0);
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
    assert(recipient_notes.len() == 1, "Incorrect transferred note count"); // 8999 UintNote x1
    assert(
        recipient_notes.get(0).get_value() == transfer_amount,
        "Incorrect transferred note amount",
    );

    // Check balances
    utils::check_private_balance(
        token_contract_address,
        owner,
        total_amount - transfer_amount,
    );
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
}

#[test(should_fail)]
// TODO(#33): error logs don't match because of raw calls
// #[test(should_fail_with = "invalid nonce")]
unconstrained fn transfer_private_failure_on_behalf_of_self_non_zero_nonce() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ false);
    // Add authwit
    let transfer_amount = U128::from_integer(1000);
    let transfer_private_from_call_interface = Token::at(token_contract_address)
        .transfer_private_to_private(owner, recipient, transfer_amount, 1);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_private_from_call_interface,
    );
    // Transfer tokens
    transfer_private_from_call_interface.call(&mut env.private());
}

#[test(should_fail)]
// #[test(should_fail_with = "Balance too low")]
unconstrained fn transfer_private_failure_on_behalf_of_more_than_balance() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ true);
    // Add authwit
    let transfer_amount = mint_amount + U128::from_integer(1);
    let transfer_private_from_call_interface = Token::at(token_contract_address)
        .transfer_private_to_private(owner, recipient, transfer_amount, 1);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_private_from_call_interface,
    );
    // Impersonate recipient to perform the call
    env.impersonate(recipient);
    // Transfer tokens
    transfer_private_from_call_interface.call(&mut env.private());
}

#[test(should_fail)]
// #[test(should_fail_with = "Authorization not found for message hash")]
unconstrained fn transfer_private_failure_on_behalf_of_other_without_approval() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ true);
    // Add authwit
    let transfer_amount = U128::from_integer(1000);
    let transfer_private_from_call_interface = Token::at(token_contract_address)
        .transfer_private_to_private(owner, recipient, transfer_amount, 1);
    // Impersonate recipient to perform the call
    env.impersonate(recipient);
    // Transfer tokens
    transfer_private_from_call_interface.call(&mut env.private());
}

#[test(should_fail)]
// #[test(should_fail_with = "Authorization not found for message hash")]
unconstrained fn transfer_private_failure_on_behalf_of_other_wrong_caller() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ true);
    // Add authwit
    let transfer_amount = U128::from_integer(1000);
    let transfer_private_from_call_interface = Token::at(token_contract_address)
        .transfer_private_to_private(owner, recipient, transfer_amount, 1);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        owner,
        transfer_private_from_call_interface,
    );
    // Impersonate recipient to perform the call
    env.impersonate(recipient);
    // Transfer tokens
    transfer_private_from_call_interface.call(&mut env.private());
}
