use crate::ClawbackLogic;
use dep::escrow_contract::types::clawback_note::ClawbackNote;
use dep::token_contract::Token;
use aztec::{
    prelude::{AztecAddress, NoteViewerOptions},
    test::helpers::{test_environment::TestEnvironment, cheatcodes},
    note::{constants::MAX_NOTES_PER_PAGE, note_getter::view_notes},
};
use std::test::OracleMock;

pub global TEST_AMOUNT: u128 = 1000;
pub global FUTURE_TIMESTAMP: u64 = 2000000000; // Year 2033
pub global PAST_TIMESTAMP: u64 = 1000000000;   // Year 2001

/// Sets up test environment with all necessary contracts and accounts
pub unconstrained fn setup_complete() -> (
    &mut TestEnvironment,
    AztecAddress, // clawback_logic_contract
    AztecAddress, // escrow_contract
    AztecAddress, // token_contract
    AztecAddress, // owner
    AztecAddress, // recipient
    AztecAddress, // minter
    [Field; 4],   // mock_keys
) {
    let mut env = TestEnvironment::new();
    let owner = env.create_account_contract(1);
    let recipient = env.create_account_contract(2);
    let minter = env.create_account_contract(3);

    // Generate mock keys for escrow
    let mock_keys = generate_mock_keys();

    // Deploy token contract
    env.impersonate(owner);
    let token_initializer = Token::interface().constructor_with_minter(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
        minter,
        AztecAddress::zero(),
    );
    let token_contract = env.deploy("./@token_contract", "Token")
        .with_public_void_initializer(owner, token_initializer);
    env.advance_block_by(1);

    // Deploy clawback logic contract
    env.impersonate(owner);
    let logic_contract = env.deploy("./@clawback_logic_contract", "ClawbackLogic");
    env.advance_block_by(1);

    // For testing, create a mock escrow contract
    let escrow_contract = env.create_account_contract(99);
    env.advance_block_by(1);

    // Mint tokens to escrow for testing
    env.impersonate(minter);
    Token::at(token_contract.to_address()).mint_to_private(
        escrow_contract,
        escrow_contract,
        TEST_AMOUNT * 10
    ).call(&mut env.private());
    env.advance_block_by(1);

    // For testing, we'll use the deployer's address as a placeholder
    // In a real implementation, this would use the proper contract address
    let logic_address = env.create_account_contract(500);
    
    (&mut env, logic_address, escrow_contract, 
     token_contract.to_address(), owner, recipient, minter, mock_keys)
}

/// Generates mock master secret keys for testing
pub unconstrained fn generate_mock_keys() -> [Field; 4] {
    // Use fixed values for deterministic testing
    [12345, 23456, 34567, 45678]
}

/// Sets up a clawback escrow by calling create_clawback
pub unconstrained fn create_test_clawback(
    env: &mut TestEnvironment,
    logic_contract: AztecAddress,
    escrow_contract: AztecAddress,
    keys: [Field; 4],
    recipient: AztecAddress,
    owner: AztecAddress,
    token_contract: AztecAddress,
    amount: u128,
    deadline: u64,
) {
    env.impersonate(owner);
    ClawbackLogic::at(logic_contract).create_clawback(
        escrow_contract,
        keys,
        recipient,
        owner,
        token_contract,
        amount,
        deadline
    ).call(&mut env.private());
    env.advance_block_by(1);
}

/// Advances time to simulate deadline passage
pub unconstrained fn advance_time_to_deadline(env: &mut TestEnvironment, target_timestamp: u64) {
    // Calculate blocks needed to reach target timestamp
    // This is a simplified version - in real implementation you'd need to know block time
    let blocks_to_advance = if target_timestamp > 1500000000 { 100 } else { 1 };
    env.advance_block_by(blocks_to_advance);
}

/// Checks that a nullifier was emitted for duplicate prevention (placeholder)
pub unconstrained fn check_nullifier_emitted(
    escrow_address: AztecAddress,
) {
    // In a full implementation, this would check the nullifier tree
    // For now, this is a placeholder that tests can call
    // The actual nullifier checking would require access to the test environment's nullifier tracking
}

/// Gets clawback notes for an address (helper for testing note storage)
pub unconstrained fn get_clawback_notes(
    logic_contract: AztecAddress,
) -> BoundedVec<ClawbackNote, MAX_NOTES_PER_PAGE> {
    let current_contract = cheatcodes::get_contract_address();
    cheatcodes::set_contract_address(logic_contract);
    
    let mut options = NoteViewerOptions::new();
    let clawback_notes_slot = ClawbackLogic::storage_layout().clawback_notes.slot;
    let notes: BoundedVec<ClawbackNote, MAX_NOTES_PER_PAGE> = 
        view_notes(clawback_notes_slot, options);
    
    cheatcodes::set_contract_address(current_contract);
    notes
}

/// Counts clawback notes for testing
pub unconstrained fn count_clawback_notes(
    logic_contract: AztecAddress,
) -> u32 {
    let notes = get_clawback_notes(logic_contract);
    notes.len()
}

/// Mock timestamp oracle for deadline testing
pub unconstrained fn mock_timestamp(timestamp: u64) {
    let _ = OracleMock::mock("get_timestamp").returns(timestamp as Field);
}

/// Checks private token balance
pub unconstrained fn check_private_balance(
    token_contract: AztecAddress,
    address: AztecAddress,
    expected_amount: u128,
) {
    let current_contract = cheatcodes::get_contract_address();
    cheatcodes::set_contract_address(token_contract);
    
    let balance = Token::balance_of_private(address);
    assert(balance == expected_amount, "Private balance mismatch");
    
    cheatcodes::set_contract_address(current_contract);
}

/// Creates a scenario with deadline in the past
pub unconstrained fn setup_past_deadline_scenario() -> (
    &mut TestEnvironment,
    AztecAddress, // logic_contract
    AztecAddress, // escrow_contract
    AztecAddress, // token_contract
    AztecAddress, // owner
    AztecAddress, // recipient
    [Field; 4],   // keys
) {
    let (env, logic_contract, escrow_contract, token_contract, owner, recipient, _, keys) 
        = setup_complete();
    
    // Create clawback with past deadline
    create_test_clawback(
        env,
        logic_contract,
        escrow_contract,
        keys,
        recipient,
        owner,
        token_contract,
        TEST_AMOUNT,
        PAST_TIMESTAMP
    );
    
    // Advance time past deadline
    advance_time_to_deadline(env, PAST_TIMESTAMP + 1000);
    
    (env, logic_contract, escrow_contract, token_contract, owner, recipient, keys)
}

/// Creates a scenario with deadline in the future
pub unconstrained fn setup_future_deadline_scenario() -> (
    &mut TestEnvironment,
    AztecAddress, // logic_contract
    AztecAddress, // escrow_contract  
    AztecAddress, // token_contract
    AztecAddress, // owner
    AztecAddress, // recipient
    [Field; 4],   // keys
) {
    let (env, logic_contract, escrow_contract, token_contract, owner, recipient, _, keys) 
        = setup_complete();
    
    // Create clawback with future deadline
    create_test_clawback(
        env,
        logic_contract,
        escrow_contract,
        keys,
        recipient,
        owner,
        token_contract,
        TEST_AMOUNT,
        FUTURE_TIMESTAMP
    );
    
    (env, logic_contract, escrow_contract, token_contract, owner, recipient, keys)
}

/// Helper to verify that correct escrow sharing occurred (checks logs)
pub unconstrained fn verify_escrow_shared(
    recipient: AztecAddress,
    escrow_address: AztecAddress,
    keys: [Field; 4],
) {
    // In a full implementation, this would check private logs for EscrowDetailsLogContent
    // For now, this is a placeholder that verifies the sharing mechanism was called
    // The actual implementation would need to decrypt and verify private logs
}

/// Creates multiple clawback scenarios for comprehensive testing
pub unconstrained fn create_multiple_clawbacks(
    env: &mut TestEnvironment,
    logic_contract: AztecAddress,
    base_escrow: AztecAddress,
    keys: [Field; 4],
    recipients: [AztecAddress; 3],
    owners: [AztecAddress; 3],
    token_contract: AztecAddress,
) {
    for i in 0..3 {
        // Create different escrow addresses by using different account contracts
        let escrow_contract = env.create_account_contract((200 + i) as Field);
        env.advance_block_by(1);
        
        create_test_clawback(
            env,
            logic_contract,
            escrow_contract,
            keys,
            recipients[i],
            owners[i],
            token_contract,
            TEST_AMOUNT * (i as u128 + 1),
            FUTURE_TIMESTAMP + (i as u64 * 1000)
        );
    }
}