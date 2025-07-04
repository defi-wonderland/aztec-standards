use crate::test::utils;
use crate::Token;
use authwit::cheatcodes as authwit_cheatcodes;
use uint_note::uint_note::PartialUintNote;

#[test]
unconstrained fn test_transfer_private_to_public_with_commitment() {
    // Setup once with account contracts since we need authwit
    let (env, token_contract_address, owner, recipient) = utils::setup_with_minter(true);
    let minter = owner; // Owner is the minter in this setup
    
    // Mint a large amount once for all tests
    let initial_mint_amount: u128 = 1_000_000;
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_private(owner, owner, initial_mint_amount).call(&mut env.private());
    env.advance_block_by(1);
    
    // Track balances throughout tests
    let mut owner_private_balance = initial_mint_amount;
    let mut owner_public_balance: u128 = 0;
    let mut recipient_private_balance: u128 = 0;
    let mut recipient_public_balance: u128 = 0;
    
    // Success case 1: Basic transfer private to public with commitment
    env.impersonate(owner);
    let transfer_amount_1 = 50_000;
    let commitment_1 = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount_1, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
    
    owner_private_balance -= transfer_amount_1;
    recipient_public_balance += transfer_amount_1;
    utils::check_private_balance(token_contract_address, owner, owner_private_balance);
    utils::check_public_balance(token_contract_address, recipient, recipient_public_balance);
    
    // Success case 2: Verify validity nullifier is emitted
    env.impersonate(owner);
    let transfer_amount_2 = 30_000;
    let commitment_2 = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount_2, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
    
    owner_private_balance -= transfer_amount_2;
    recipient_public_balance += transfer_amount_2;
    
    // Check validity nullifier exists
    let validity_commitment = PartialUintNote { commitment: commitment_2 }.compute_validity_commitment(owner);
    assert(
        env.public().nullifier_exists(validity_commitment, token_contract_address),
        "validity nullifier should exist",
    );
    
    // Success case 3: Transfer on behalf of other with authwit
    let transfer_amount_3 = 20_000;
    let transfer_call_3 = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount_3, 0);
    
    authwit_cheatcodes::add_private_authwit_from_call_interface(owner, recipient, transfer_call_3);
    
    env.impersonate(recipient);
    let commitment_3 = transfer_call_3.call(&mut env.private());
    env.advance_block_by(1);
    
    owner_private_balance -= transfer_amount_3;
    recipient_public_balance += transfer_amount_3;
    utils::check_private_balance(token_contract_address, owner, owner_private_balance);
    utils::check_public_balance(token_contract_address, recipient, recipient_public_balance);
    
    // Success case 4: Transfer with commitment and finalize (complete flow)
    env.impersonate(owner);
    let transfer_amount_4 = 40_000;
    let commitment_4 = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount_4, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
    
    owner_private_balance -= transfer_amount_4;
    recipient_public_balance += transfer_amount_4;
    utils::check_public_balance(token_contract_address, recipient, recipient_public_balance);
    
    // Now finalize by transferring from public to commitment
    env.impersonate(recipient);
    let finalize_action = Token::at(token_contract_address).transfer_public_to_commitment(
        recipient,
        commitment_4,
        transfer_amount_4,
        0,
    );
    authwit_cheatcodes::add_public_authwit_from_call_interface(recipient, owner, finalize_action);
    
    env.impersonate(owner);
    finalize_action.call(&mut env.public());
    env.advance_block_by(1);
    
    // After finalization, tokens should be in recipient's private balance
    recipient_public_balance -= transfer_amount_4;
    recipient_private_balance += transfer_amount_4;
    utils::check_private_balance(token_contract_address, owner, owner_private_balance);
    utils::check_public_balance(token_contract_address, recipient, recipient_public_balance);
    utils::check_private_balance(token_contract_address, recipient, recipient_private_balance);
    
    // Failure case 1: Finalize with invalid commitment
    // "Invalid partial note or completer"
    env.impersonate(owner);
    let transfer_amount_5 = 25_000;
    let _ = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount_5, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
    
    owner_private_balance -= transfer_amount_5;
    recipient_public_balance += transfer_amount_5;
    
    // Try to finalize with invalid commitment
    let invalid_commitment = 0xdeadbeef;
    env.impersonate(recipient);
    let invalid_finalize_call = Token::at(token_contract_address)
        .transfer_public_to_commitment(recipient, invalid_commitment, transfer_amount_5, 0);
    env.assert_public_call_fails(invalid_finalize_call);
    
    // Balances should remain unchanged (transfer_amount_5 stays in recipient's public balance)
    utils::check_public_balance(token_contract_address, recipient, recipient_public_balance);
    utils::check_private_balance(token_contract_address, recipient, recipient_private_balance);
    
    // Failure case 2: Finalize with zero commitment
    // "Invalid partial note or completer"
    env.impersonate(owner);
    let transfer_amount_6 = 15_000;
    let _ = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount_6, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
    
    owner_private_balance -= transfer_amount_6;
    recipient_public_balance += transfer_amount_6;
    
    // Try to finalize with zero commitment
    let zero_commitment = 0;
    env.impersonate(recipient);
    let zero_finalize_call = Token::at(token_contract_address)
        .transfer_public_to_commitment(recipient, zero_commitment, transfer_amount_6, 0);
    env.assert_public_call_fails(zero_finalize_call);
    
    // Final balance verification
    utils::check_private_balance(token_contract_address, owner, owner_private_balance);
    utils::check_public_balance(token_contract_address, owner, owner_public_balance);
    utils::check_public_balance(token_contract_address, recipient, recipient_public_balance);
    utils::check_private_balance(token_contract_address, recipient, recipient_private_balance);
}