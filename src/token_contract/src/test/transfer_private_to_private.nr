use crate::test::utils::{self, mint_amount};
use crate::Token;
use aztec::{note::constants::MAX_NOTES_PER_PAGE, test::helpers::authwit as authwit_cheatcodes};
use uint_note::uint_note::UintNote;

#[test]
unconstrained fn transfer_private_on_behalf_of_other() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(true);
    // Add authwit
    let transfer_amount = (1000 as u128);
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
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(true);

    let notes_amount: u128 = 1000;
    let notes_count: u128 = 12;
    let total_amount = notes_amount * notes_count;

    env.impersonate(minter);
    for _ in 0..notes_count {
        utils::mint_to_private(env, token_contract_address, owner, notes_amount);
    }

    // Transfer tokens
    // Transfer will require 11 notes with change, which requires 2 recursive calls: 2 + 8 + 1
    env.impersonate(owner);
    // transfer amount is 10999 of the 12000 total
    let transfer_amount = total_amount - notes_amount - (1 as u128);
    let transfer_private_from_call_interface = Token::at(token_contract_address)
        .transfer_private_to_private(owner, recipient, transfer_amount, 0);
    transfer_private_from_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    // NOTE: Removing this check makes the test fail.
    let recipient_balance = utils::get_private_balance(token_contract_address, recipient);
    assert(recipient_balance == transfer_amount, "Incorrect recipient balance");

    // Check that the notes still owned by the owner are correct
    let final_owner_notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        utils::get_private_balance_notes(token_contract_address, owner, 0);
    assert(final_owner_notes.len() == 2, "Incorrect note count"); // 1000 UintNote x1 and 1 UintNote x1
    assert(final_owner_notes.get(0).get_value() == notes_amount, "Incorrect note amount");
    assert(final_owner_notes.get(1).get_value() == (1 as u128), "Incorrect note change amount");

    // Check that the notes generated to the recipient are correct
    let recipient_notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        utils::get_private_balance_notes(token_contract_address, recipient, 0);
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

#[test(should_fail_with = "Balance too low")]
unconstrained fn transfer_private_failure_on_behalf_of_more_than_balance() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(true);
    // Add authwit
    let transfer_amount = mint_amount + (1 as u128);
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

// Unknown auth witness for message hash 0x055a9af747d60526794cfa8d3cf0b506831f34a202f85f6576ac67c429962b01
#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn transfer_private_failure_on_behalf_of_other_without_approval() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(true);
    // Add authwit
    let transfer_amount = (1000 as u128);
    let transfer_private_from_call_interface = Token::at(token_contract_address)
        .transfer_private_to_private(owner, recipient, transfer_amount, 1);
    // Impersonate recipient to perform the call
    env.impersonate(recipient);
    // Transfer tokens
    transfer_private_from_call_interface.call(&mut env.private());
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn transfer_private_failure_on_behalf_of_other_wrong_caller() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(true);
    // Add authwit
    let transfer_amount: u128 = 1000;
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
