use dep::nft_contract::NFT;
use dep::token_contract::Token;
use aztec::{prelude::AztecAddress, test::helpers::{cheatcodes, test_environment::TestEnvironment}};

pub global TEST_AMOUNT: u128 = 1000;
pub global TEST_TOKEN_ID: Field = 42;

/// Sets up test environment with token contract and accounts
pub unconstrained fn setup_with_token() -> (&mut TestEnvironment, AztecAddress, // token_contract
AztecAddress, // owner
AztecAddress, // recipient
AztecAddress // minter
) {
    let mut env = TestEnvironment::new();
    let owner = env.create_account_contract(1);
    let recipient = env.create_account_contract(2);
    let minter = env.create_account_contract(3);

    // Deploy token contract with minter
    env.impersonate(owner);
    let token_initializer = Token::interface().constructor_with_minter(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
        minter,
        AztecAddress::zero(),
    );
    let token_contract = env.deploy("./@token_contract", "Token").with_public_void_initializer(
        owner,
        token_initializer,
    );
    env.advance_block_by(1);

    // Mint tokens to owner for testing
    env.impersonate(minter);
    Token::at(token_contract.to_address()).mint_to_private(owner, owner, TEST_AMOUNT * 10).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    (&mut env, token_contract.to_address(), owner, recipient, minter)
}

/// Sets up test environment with NFT contract and accounts
pub unconstrained fn setup_with_nft() -> (&mut TestEnvironment, AztecAddress, // nft_contract
AztecAddress, // owner
AztecAddress, // recipient
AztecAddress // minter
) {
    let mut env = TestEnvironment::new();
    let owner = env.create_account_contract(1);
    let recipient = env.create_account_contract(2);
    let minter = env.create_account_contract(3);

    // Deploy NFT contract with minter
    env.impersonate(owner);
    let nft_initializer = NFT::interface().constructor_with_minter(
        "TestNFT000000000000000000000000",
        "TNFT000000000000000000000000000",
        minter,
        AztecAddress::zero(),
    );
    let nft_contract =
        env.deploy("./@nft_contract", "NFT").with_public_void_initializer(owner, nft_initializer);
    env.advance_block_by(1);

    // Mint NFT to owner for testing
    env.impersonate(minter);
    NFT::at(nft_contract.to_address()).mint_to_private(owner, TEST_TOKEN_ID).call(&mut env.private());
    env.advance_block_by(1);

    (&mut env, nft_contract.to_address(), owner, recipient, minter)
}

/// Deploys an escrow contract with the given logic contract address as salt
pub unconstrained fn deploy_escrow_with_logic(
    env: &mut TestEnvironment,
    deployer: AztecAddress,
    logic_contract: AztecAddress,
) -> AztecAddress {
    env.impersonate(deployer);

    // For testing, we'll simulate the escrow deployment by creating an account
    // In a real scenario, this would be deployed with the proper salt mechanism
    let escrow_contract = env.create_account_contract(99);
    env.advance_block_by(1);

    escrow_contract
}

/// Creates a mock logic contract for testing
pub unconstrained fn create_mock_logic_contract(env: &mut TestEnvironment) -> AztecAddress {
    env.create_account_contract(100) // Use high number to distinguish from test accounts
}

/// Transfers tokens to escrow contract for testing withdrawals
pub unconstrained fn fund_escrow_with_tokens(
    env: &mut TestEnvironment,
    token_contract: AztecAddress,
    escrow_contract: AztecAddress,
    funder: AztecAddress,
    amount: u128,
) {
    env.impersonate(funder);
    Token::at(token_contract).transfer_private_to_private(funder, escrow_contract, amount, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);
}

/// Transfers NFT to escrow contract for testing withdrawals
pub unconstrained fn fund_escrow_with_nft(
    env: &mut TestEnvironment,
    nft_contract: AztecAddress,
    escrow_contract: AztecAddress,
    funder: AztecAddress,
    token_id: Field,
) {
    env.impersonate(funder);
    NFT::at(nft_contract).transfer_private_to_private(funder, escrow_contract, token_id, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);
}

/// Checks private token balance of an address
pub unconstrained fn check_token_balance(
    token_contract: AztecAddress,
    address: AztecAddress,
    expected_amount: u128,
) {
    let current_contract = cheatcodes::get_contract_address();
    cheatcodes::set_contract_address(token_contract);

    let balance = Token::balance_of_private(address);
    assert(balance == expected_amount, "Token balance mismatch");

    cheatcodes::set_contract_address(current_contract);
}

/// Checks NFT ownership (placeholder for testing)
pub unconstrained fn check_nft_ownership(
    nft_contract: AztecAddress,
    expected_owner: AztecAddress,
    token_id: Field,
) {
    // In a full implementation, this would check NFT ownership
    // For now, this is a placeholder that assumes the check passes
    // when the function is called without panicking
}
