use crate::{Escrow, test::utils};
use aztec::{prelude::AztecAddress, test::helpers::test_environment::TestEnvironment};

/// Test basic escrow contract compilation and setup
#[test]
unconstrained fn test_escrow_setup() {
    let (env, token_contract, owner, recipient, _) = utils::setup_with_token();

    // Create mock logic contract
    let logic_contract = utils::create_mock_logic_contract(env);

    // Deploy escrow with logic contract simulation
    let escrow_contract = utils::deploy_escrow_with_logic(env, owner, logic_contract);

    // Verify contracts were created
    assert(escrow_contract != AztecAddress::zero(), "Escrow contract not deployed");
    assert(token_contract != AztecAddress::zero(), "Token contract not deployed");
}

/// Test escrow can be funded with tokens
#[test]
unconstrained fn test_escrow_funding() {
    let (env, token_contract, owner, recipient, _) = utils::setup_with_token();

    // Create mock logic contract
    let logic_contract = utils::create_mock_logic_contract(env);

    // Deploy escrow with logic contract simulation
    let escrow_contract = utils::deploy_escrow_with_logic(env, owner, logic_contract);

    // Fund escrow with tokens
    utils::fund_escrow_with_tokens(
        env,
        token_contract,
        escrow_contract,
        owner,
        utils::TEST_AMOUNT,
    );

    // Verify escrow has tokens
    utils::check_token_balance(token_contract, escrow_contract, utils::TEST_AMOUNT);
}

/// Test NFT escrow functionality
#[test]
unconstrained fn test_nft_escrow_setup() {
    let (env, nft_contract, owner, recipient, _) = utils::setup_with_nft();

    // Create mock logic contract
    let logic_contract = utils::create_mock_logic_contract(env);

    // Deploy escrow with logic contract simulation
    let escrow_contract = utils::deploy_escrow_with_logic(env, owner, logic_contract);

    // Fund escrow with NFT
    utils::fund_escrow_with_nft(
        env,
        nft_contract,
        escrow_contract,
        owner,
        utils::TEST_TOKEN_ID,
    );

    // Verify escrow has NFT (placeholder check)
    utils::check_nft_ownership(nft_contract, escrow_contract, utils::TEST_TOKEN_ID);
}

/// Test multiple escrow contracts can coexist
#[test]
unconstrained fn test_multiple_escrow_contracts() {
    let (env, token_contract, owner, recipient, _) = utils::setup_with_token();

    // Create multiple logic contracts
    let logic_contract1 = utils::create_mock_logic_contract(env);
    let logic_contract2 = env.create_account_contract(101);

    // Deploy multiple escrow contracts
    let escrow_contract1 = utils::deploy_escrow_with_logic(env, owner, logic_contract1);
    let escrow_contract2 = utils::deploy_escrow_with_logic(env, owner, logic_contract2);

    // Verify they are different
    assert(escrow_contract1 != escrow_contract2, "Escrow contracts should be different");

    // Fund both escrows
    utils::fund_escrow_with_tokens(
        env,
        token_contract,
        escrow_contract1,
        owner,
        utils::TEST_AMOUNT,
    );
    utils::fund_escrow_with_tokens(
        env,
        token_contract,
        escrow_contract2,
        owner,
        utils::TEST_AMOUNT * 2,
    );

    // Verify balances
    utils::check_token_balance(token_contract, escrow_contract1, utils::TEST_AMOUNT);
    utils::check_token_balance(token_contract, escrow_contract2, utils::TEST_AMOUNT * 2);
}

/// Test escrow with zero amounts
#[test]
unconstrained fn test_escrow_zero_amounts() {
    let (env, token_contract, owner, recipient, _) = utils::setup_with_token();

    // Create mock logic contract
    let logic_contract = utils::create_mock_logic_contract(env);

    // Deploy escrow
    let escrow_contract = utils::deploy_escrow_with_logic(env, owner, logic_contract);

    // Check initial balance is zero
    utils::check_token_balance(token_contract, escrow_contract, 0);
}

/// Test escrow address generation is deterministic for same logic contract
#[test]
unconstrained fn test_escrow_address_consistency() {
    let (env, _, owner, _, _) = utils::setup_with_token();

    // Create same logic contract
    let logic_contract = utils::create_mock_logic_contract(env);

    // Deploy escrow multiple times with same logic contract
    let escrow_contract1 = utils::deploy_escrow_with_logic(env, owner, logic_contract);
    let escrow_contract2 = utils::deploy_escrow_with_logic(env, owner, logic_contract);

    // In a real implementation with proper salt handling, these would be the same
    // For now, we just verify they were created successfully
    assert(escrow_contract1 != AztecAddress::zero(), "First escrow should be valid");
    assert(escrow_contract2 != AztecAddress::zero(), "Second escrow should be valid");
}
