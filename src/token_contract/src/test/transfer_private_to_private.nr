use crate::test::utils;
use crate::Token;
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::note::constants::MAX_NOTES_PER_PAGE;
use uint_note::uint_note::UintNote;

#[test]
unconstrained fn test_transfer_private_to_private() {
    // Setup once with account contracts since we need authwit
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(true);

    // Mint a large amount once for all tests
    let initial_mint_amount: u128 = 1_000_000;
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_private(owner, owner, initial_mint_amount).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Track balance throughout tests
    let mut owner_balance = initial_mint_amount;
    let mut recipient_balance: u128 = 0;

    // Success case 1: Transfer on behalf of other with authwit
    let transfer_amount_1 = 1_000;
    let transfer_private_call_1 = Token::at(token_contract_address).transfer_private_to_private(
        owner,
        recipient,
        transfer_amount_1,
        1,
    );
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_private_call_1,
    );

    env.impersonate(recipient);
    transfer_private_call_1.call(&mut env.private());

    owner_balance -= transfer_amount_1;
    recipient_balance += transfer_amount_1;
    utils::check_private_balance(token_contract_address, owner, owner_balance);
    utils::check_private_balance(token_contract_address, recipient, recipient_balance);

    // Success case 2: Transfer multiple notes recursively
    // First mint multiple notes to create a fragmented balance
    let notes_amount: u128 = 1_000;
    let notes_count: u128 = 12;
    let fragmented_amount = notes_amount * notes_count;

    env.impersonate(minter);
    for _ in 0..notes_count {
        utils::mint_to_private(env, token_contract_address, owner, notes_amount);
    }
    owner_balance += fragmented_amount;

    // Transfer will require 11 notes with change, which requires 2 recursive calls
    env.impersonate(owner);
    let transfer_amount_2 = fragmented_amount - notes_amount - 1;
    let transfer_private_call_2 = Token::at(token_contract_address).transfer_private_to_private(
        owner,
        recipient,
        transfer_amount_2,
        0,
    );
    transfer_private_call_2.call(&mut env.private());
    env.advance_block_by(1);

    owner_balance -= transfer_amount_2;
    recipient_balance += transfer_amount_2;

    // Verify recipient balance
    let actual_recipient_balance = utils::get_private_balance(token_contract_address, recipient);
    assert(actual_recipient_balance == recipient_balance, "Incorrect recipient balance");

    // Check that the notes still owned by the owner are correct
    let final_owner_notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        utils::get_private_balance_notes(token_contract_address, owner, 0);
    assert(final_owner_notes.len() >= 2, "Incorrect note count");

    // Check that the notes generated to the recipient are correct
    let recipient_notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        utils::get_private_balance_notes(token_contract_address, recipient, 0);
    assert(recipient_notes.len() >= 1, "Incorrect transferred note count");

    // Final balance checks
    utils::check_private_balance(token_contract_address, owner, owner_balance);
    utils::check_private_balance(token_contract_address, recipient, recipient_balance);

    // Failure case 1: Transfer more than balance
    // "Balance too low"
    let excessive_amount = owner_balance + 100_000;
    let excessive_transfer_call = Token::at(token_contract_address).transfer_private_to_private(
        owner,
        recipient,
        excessive_amount,
        1,
    );
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        excessive_transfer_call,
    );

    env.impersonate(recipient);
    env.assert_private_call_fails(excessive_transfer_call);

    // Failure case 2: Transfer without authwit
    // "Unknown auth witness for message hash"
    let unauthorized_amount = 1_000;
    let unauthorized_transfer_call = Token::at(token_contract_address).transfer_private_to_private(
        owner,
        recipient,
        unauthorized_amount,
        1,
    );

    env.impersonate(recipient);
    env.assert_private_call_fails(unauthorized_transfer_call);

    // Failure case 3: Transfer with wrong caller in authwit
    // "Unknown auth witness for message hash"
    let wrong_caller_amount = 1_000;
    let wrong_caller_transfer_call = Token::at(token_contract_address).transfer_private_to_private(
        owner,
        recipient,
        wrong_caller_amount,
        1,
    );
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        owner, // Wrong! Should be recipient
        wrong_caller_transfer_call,
    );

    env.impersonate(recipient);
    env.assert_private_call_fails(wrong_caller_transfer_call);

    // Balances should remain unchanged after failed transfers
    utils::check_private_balance(token_contract_address, owner, owner_balance);
    utils::check_private_balance(token_contract_address, recipient, recipient_balance);
}
