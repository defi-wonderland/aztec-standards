use crate::SFT;
use aztec::{
    oracle::{execution::{get_block_number, get_contract_address}, storage::storage_read},
    prelude::AztecAddress,
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
};

pub global token_id_1: Field = 101;
pub global token_id_2: Field = 202;
pub global token_id_3: Field = 303;

/// Setup function with minter role for comprehensive SFT testing
pub unconstrained fn setup_with_minter(
    with_account_contracts: bool,
) -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let (owner, minter, recipient) = if with_account_contracts {
        let owner = env.create_account_contract(1);
        let minter = env.create_account_contract(2);
        let recipient = env.create_account_contract(3);
        env.advance_block_by(1);
        (owner, minter, recipient)
    } else {
        // For simple tests without authorization, use regular accounts
        let owner = env.create_account(1);
        let minter = env.create_account(2);
        let recipient = env.create_account(3);
        (owner, minter, recipient)
    };

    let sft_contract_address = deploy_sft_with_minter(&mut env, owner, minter);
    env.advance_block_by(1);

    (&mut env, sft_contract_address, owner, minter, recipient)
}

/// Deploy SFT contract with minter
pub unconstrained fn deploy_sft_with_minter(
    env: &mut TestEnvironment,
    owner: AztecAddress,
    minter: AztecAddress,
) -> AztecAddress {
    env.impersonate(owner);

    let initializer_call_interface = SFT::interface().constructor_with_minter(
        "TestSFT000000000000000000000000",
        "TSFT000000000000000000000000000",
        minter,
        AztecAddress::zero(),
    );
    let sft_contract = env.deploy("./@sft_contract", "SFT").with_public_void_initializer(
        owner,
        initializer_call_interface,
    );
    env.advance_block_by(1);

    sft_contract.to_address()
}

/// Setup and mint to private with minter
pub unconstrained fn setup_and_mint_to_private(
    with_account_contracts: bool,
) -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (env, sft_contract_address, owner, minter, recipient) =
        setup_with_minter(with_account_contracts);

    env.impersonate(minter);
    SFT::at(sft_contract_address).create_token_type(token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).create_token_type(token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    // Mint some SFTs to private
    SFT::at(sft_contract_address).mint_to_private(owner, token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, token_id_2).call(&mut env.private());
    env.advance_block_by(1);

    (env, sft_contract_address, owner, minter, recipient)
}

/// Setup and mint to public with minter
pub unconstrained fn setup_and_mint_to_public(
    with_account_contracts: bool,
) -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (env, sft_contract_address, owner, minter, recipient) =
        setup_with_minter(with_account_contracts);

    env.impersonate(minter);
    SFT::at(sft_contract_address).create_token_type(token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).create_token_type(token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    // Mint some SFTs to public
    SFT::at(sft_contract_address).mint_to_public(owner, token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(owner, token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(owner, token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    (env, sft_contract_address, owner, minter, recipient)
}

pub unconstrained fn check_private_balance(
    sft_contract_address: AztecAddress,
    owner: AztecAddress,
    token_id: Field,
    expected_balance: u128,
) {
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(sft_contract_address);
    // Direct call to utility function
    let balance = SFT::balance_of_private_set_per_page(owner, token_id, 0);
    cheatcodes::set_contract_address(current_contract_address);
    assert(balance == expected_balance, "Private balance mismatch");
}

pub unconstrained fn check_public_balance(
    env: &mut TestEnvironment,
    sft_contract_address: AztecAddress,
    owner: AztecAddress,
    token_id: Field,
    expected_balance: u128,
) {
    let balance = SFT::at(sft_contract_address).balance_of_public_by_token_id(owner, token_id).view(
        &mut env.public(),
    );
    assert(balance == expected_balance, "Public balance mismatch");
}

pub unconstrained fn check_total_supply(
    env: &mut TestEnvironment,
    sft_contract_address: AztecAddress,
    token_id: Field,
    expected_supply: u128,
) {
    let supply = SFT::at(sft_contract_address).total_supply(token_id).view(&mut env.public());
    assert(supply == expected_supply, "Total supply mismatch");
}

pub unconstrained fn check_token_type_exists(
    env: &mut TestEnvironment,
    sft_contract_address: AztecAddress,
    token_id: Field,
    expected_exists: bool,
) {
    let exists =
        SFT::at(sft_contract_address).public_token_type_exists(token_id).view(&mut env.public());
    assert(exists == expected_exists, "Token type existence mismatch");
}

pub unconstrained fn create_test_token_type(
    env: &mut TestEnvironment,
    sft_contract_address: AztecAddress,
    minter: AztecAddress,
) {
    env.impersonate(minter);
    SFT::at(sft_contract_address).create_token_type(token_id_1).call(&mut env.public());
    env.advance_block_by(1);
}

pub unconstrained fn get_commitment_stored(
    sft_contract_address: AztecAddress,
    commitment: Field,
) -> bool {
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(sft_contract_address);
    let block_number = get_block_number();

    let stored: bool = storage_read(sft_contract_address, commitment, block_number);

    cheatcodes::set_contract_address(current_contract_address);
    stored
}
