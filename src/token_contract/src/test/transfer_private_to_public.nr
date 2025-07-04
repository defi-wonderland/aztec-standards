use crate::test::utils;
use crate::Token;
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::note::constants::MAX_NOTES_PER_PAGE;
use uint_note::uint_note::UintNote;

#[test]
unconstrained fn test_transfer_private_to_public() {
    // Setup once with account contracts since we need authwit
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(true);
    
    // Mint a large amount once for all tests
    let initial_mint_amount: u128 = 1_000_000;
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_private(owner, owner, initial_mint_amount).call(&mut env.private());
    env.advance_block_by(1);
    
    // Track balances throughout tests
    let mut owner_private_balance = initial_mint_amount;
    let mut owner_public_balance: u128 = 0;
    let mut recipient_public_balance: u128 = 0;
    
    // Success case 1: Transfer private to public on behalf of self
    env.impersonate(owner);
    let transfer_amount_1 = 50_000;
    Token::at(token_contract_address)
        .transfer_private_to_public(owner, owner, transfer_amount_1, 0)
        .call(&mut env.private());
    
    owner_private_balance -= transfer_amount_1;
    owner_public_balance += transfer_amount_1;
    utils::check_private_balance(token_contract_address, owner, owner_private_balance);
    utils::check_public_balance(token_contract_address, owner, owner_public_balance);
    
    // Success case 2: Transfer private to public on behalf of other with authwit
    let transfer_amount_2 = 30_000;
    let transfer_call_2 = Token::at(token_contract_address)
        .transfer_private_to_public(owner, recipient, transfer_amount_2, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(owner, recipient, transfer_call_2);
    
    env.impersonate(recipient);
    transfer_call_2.call(&mut env.private());
    
    owner_private_balance -= transfer_amount_2;
    recipient_public_balance += transfer_amount_2;
    utils::check_private_balance(token_contract_address, owner, owner_private_balance);
    utils::check_public_balance(token_contract_address, recipient, recipient_public_balance);
    
    // Success case 3: Transfer multiple notes recursively
    // First mint multiple notes to create fragmented balance
    let notes_amount = 1_000;
    let notes_count = 12;
    let fragmented_amount = notes_amount * notes_count;
    
    env.impersonate(minter);
    for _ in 0..notes_count {
        utils::mint_to_private(env, token_contract_address, owner, notes_amount);
    }
    owner_private_balance += fragmented_amount;
    
    // Transfer will require 11 notes with change, which requires 2 recursive calls
    env.impersonate(owner);
    let transfer_amount_3 = fragmented_amount - notes_amount - 1;
    let transfer_call_3 = Token::at(token_contract_address)
        .transfer_private_to_public(owner, recipient, transfer_amount_3, 0);
    transfer_call_3.call(&mut env.private());
    env.advance_block_by(1);
    
    owner_private_balance -= transfer_amount_3;
    recipient_public_balance += transfer_amount_3;
    
    // Verify owner balance
    let actual_owner_balance = utils::get_private_balance(token_contract_address, owner);
    assert(actual_owner_balance == owner_private_balance, "Incorrect owner balance");
    
    // Check remaining notes structure
    let final_owner_notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        utils::get_private_balance_notes(token_contract_address, owner, 0);
    assert(final_owner_notes.len() >= 2, "Incorrect note count");
    
    // Verify no private notes were sent to recipient (only public balance)
    let recipient_private_notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        utils::get_private_balance_notes(token_contract_address, recipient, 0);
    assert(recipient_private_notes.len() == 0, "Incorrect transferred note count");
    
    // Final balance checks
    utils::check_private_balance(token_contract_address, owner, owner_private_balance);
    utils::check_public_balance(token_contract_address, recipient, recipient_public_balance);
    
    // Failure case 1: Transfer more than balance
    // "Balance too low"
    env.impersonate(owner);
    let excessive_amount = owner_private_balance + 100_000;
    let excessive_transfer_call = Token::at(token_contract_address)
        .transfer_private_to_public(owner, owner, excessive_amount, 0);
    env.assert_private_call_fails(excessive_transfer_call);
    
    // Failure case 2: Transfer more than balance on behalf of other (with authwit)
    // "Balance too low"
    let excessive_transfer_call_2 = Token::at(token_contract_address)
        .transfer_private_to_public(owner, recipient, excessive_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(owner, recipient, excessive_transfer_call_2);
    
    env.impersonate(recipient);
    env.assert_private_call_fails(excessive_transfer_call_2);
    
    // Failure case 3: Transfer with wrong designated caller
    // "Unknown auth witness for message hash"
    let wrong_caller_amount = 5_000;
    let wrong_caller_call = Token::at(token_contract_address)
        .transfer_private_to_public(owner, recipient, wrong_caller_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(owner, owner, wrong_caller_call);
    
    env.impersonate(recipient);
    env.assert_private_call_fails(wrong_caller_call);
    
    // Failure case 4: Transfer without authwit
    // "Unknown auth witness for message hash"
    let unauthorized_amount = 5_000;
    let unauthorized_call = Token::at(token_contract_address)
        .transfer_private_to_public(owner, recipient, unauthorized_amount, 0);
    
    env.impersonate(recipient);
    env.assert_private_call_fails(unauthorized_call);
    
    // Balances should remain unchanged after failed transfers
    utils::check_private_balance(token_contract_address, owner, owner_private_balance);
    utils::check_public_balance(token_contract_address, owner, owner_public_balance);
    utils::check_public_balance(token_contract_address, recipient, recipient_public_balance);
}