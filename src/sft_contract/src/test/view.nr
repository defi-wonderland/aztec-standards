use crate::SFT;
use crate::test::utils;
use compressed_string::FieldCompressedString;

/// Test that SFT name is correctly set during deployment
#[test]
unconstrained fn sft_name_is_set() {
    let (env, sft_contract_address, _, _, _) = utils::setup_with_minter(false);
    let name = SFT::at(sft_contract_address).public_get_name().view(&mut env.public());
    let expected_name = FieldCompressedString::from_string("TestSFT000000000000000000000000");
    assert(name == expected_name, "name is not set correctly");
}

/// Test that SFT symbol is correctly set during deployment
#[test]
unconstrained fn sft_symbol_is_set() {
    let (env, sft_contract_address, _, _, _) = utils::setup_with_minter(false);
    let symbol = SFT::at(sft_contract_address).public_get_symbol().view(&mut env.public());
    let expected_symbol = FieldCompressedString::from_string("TSFT000000000000000000000000000");
    assert(symbol == expected_symbol, "symbol is not set correctly");
}

/// Test that token type doesn't exist initially
#[test]
unconstrained fn token_type_does_not_exist_initially() {
    let (env, sft_contract_address, _, _, _) = utils::setup_with_minter(false);
    let exists = SFT::at(sft_contract_address)
        .public_token_type_exists(utils::token_id_1)
        .view(&mut env.public());
    assert(!exists, "token type should not exist initially");
}

/// Test that token type exists after creation
#[test]
unconstrained fn token_type_exists_after_creation() {
    let (env, sft_contract_address, _, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    utils::check_token_type_exists(env, sft_contract_address, utils::token_id_1, true);
}

/// Test that public balance is zero initially
#[test]
unconstrained fn public_balance_is_zero_initially() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 0);
}

/// Test that total supply is zero initially
#[test]
unconstrained fn total_supply_is_zero_initially() {
    let (env, sft_contract_address, _, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 0);
}

/// Test that private balance is zero initially
#[test]
unconstrained fn private_balance_is_zero_initially() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 0);
}