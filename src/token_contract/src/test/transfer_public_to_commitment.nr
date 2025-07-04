use crate::{test::utils, Token};
use aztec::oracle::random::random;
use std::test::OracleMock;

#[test]
unconstrained fn test_transfer_public_to_commitment_all_cases() {
    // Setup with large initial mint for all test cases
    let initial_mint = 1_000_000;
    let (env, token_contract_address, owner, recipient) =
        utils::setup_with_initial_supply(false, initial_mint);
    
    // Test 1: Internal orchestration flow
    // This test verifies the helper function that handles both initialize and transfer steps
    let (env2, token_contract_address2, user, _) = 
        utils::setup_and_mint_to_private_without_minter(false);
    utils::check_private_balance(token_contract_address2, user, utils::mint_amount);
    
    // Test 2: External orchestration flow (manual initialize and finalize)
    let transfer_amount = 100_000;
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);
    
    // Prepare the transfer
    let commitment = Token::at(token_contract_address)
        .initialize_transfer_commitment(owner, recipient, owner)
        .call(&mut env.private());
    
    // Finalize the transfer
    Token::at(token_contract_address)
        .transfer_public_to_commitment(owner, commitment, transfer_amount, 0)
        .call(&mut env.public());
    
    env.advance_block_by(1);
    
    // Check recipient received tokens privately
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
    utils::check_public_balance(token_contract_address, owner, initial_mint - transfer_amount);
    
    // Test 3: Transfer not initialized failure
    let invalid_commitment = random();
    
    // Expected error: Invalid partial note or completer 'context.nullifier_exists(validity_commitment, context.this_address())'
    env.assert_public_call_fails(
        Token::at(token_contract_address)
            .transfer_public_to_commitment(owner, invalid_commitment, transfer_amount, 0)
    );
    
    // Test 4: Not an owner failure
    let not_owner = env.create_account();
    
    // Prepare commitment for the failure case
    let commitment_fail = Token::at(token_contract_address)
        .initialize_transfer_commitment(owner, not_owner, owner)
        .call(&mut env.private());
    
    env.impersonate(not_owner);
    
    // Expected error: attempt to subtract with overflow 'public_balances.at(from).read() - amount'
    env.assert_public_call_fails(
        Token::at(token_contract_address)
            .transfer_public_to_commitment(not_owner, commitment_fail, transfer_amount, 0)
    );
}
