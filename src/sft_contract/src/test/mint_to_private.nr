use crate::SFT;
use crate::test::utils;

/// Test successful private minting
#[test]
unconstrained fn mint_to_private_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
}

/// Test private balance after multiple mints
#[test]
unconstrained fn private_balance_after_minting_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 2);
}

/// Test that total supply increases after private minting
#[test]
unconstrained fn total_supply_increases_after_private_minting_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 2);
}

/// Test that total supply increases with mixed public and private minting
#[test]
unconstrained fn total_supply_increases_mixed_minting_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 2);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
}

/// Test that private balances are separate for different token types
#[test]
unconstrained fn mint_to_private_separate_token_types_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.impersonate(minter);
    SFT::at(sft_contract_address).create_token_type(utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).create_token_type(utils::token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_2).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_2).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_2, 2);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 1);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_2, 2);
}

/// Test that private balances are separate for different owners
#[test]
unconstrained fn mint_to_private_separate_owners_success() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);

    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(recipient, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(recipient, utils::token_id_1).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 2);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 3);
}

/// Test private and public balances are independent
#[test]
unconstrained fn private_public_balances_independent_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 2);
}


/// Test minting fails without minter role
#[test(should_fail_with = "caller is not minter")]
unconstrained fn mint_to_private_not_minter_fail() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);

    env.impersonate(recipient);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
}

/// Test minting succeeds even without pre-existing token type (auto-creates)
#[test]
unconstrained fn mint_to_private_auto_creates_token_type_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_token_type_exists(env, sft_contract_address, utils::token_id_1, true);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 1);
}

/// Test minting fails with zero token ID
#[test(should_fail_with = "zero token ID not supported")]
unconstrained fn mint_to_private_zero_token_id_fail() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, 0).call(&mut env.private());
}
