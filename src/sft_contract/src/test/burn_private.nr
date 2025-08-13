use crate::SFT;
use crate::test::utils;

/// Test successful private burning
#[test]
unconstrained fn burn_private_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_and_mint_to_private(false);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 2);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 2);

    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_private(owner, utils::token_id_1, 0).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 1);
}

/// Test total supply decreases after private burning
#[test]
unconstrained fn burn_private_total_supply_decreases_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 3);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 3);

    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_private(owner, utils::token_id_1, 0).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 2);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 2);
}

/// Test burning with mixed public and private balances
#[test]
unconstrained fn burn_private_mixed_balances_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);

    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_private(owner, utils::token_id_1, 0).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 0);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
}

/// Test burning is isolated per token type
#[test]
unconstrained fn burn_private_separate_token_types_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.impersonate(minter);
    SFT::at(sft_contract_address).create_token_type(utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).create_token_type(utils::token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_2).call(&mut env.private());
    env.advance_block_by(1);

    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_private(owner, utils::token_id_1, 0).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_2, 1);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 1);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_2, 1);
}

/// Test burning is isolated per owner
#[test]
unconstrained fn burn_private_separate_owners_success() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);

    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(recipient, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(recipient, utils::token_id_1).call(&mut env.private());
    env.advance_block_by(1);

    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_private(owner, utils::token_id_1, 0).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 0);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 2);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 2);
}


/// Test burning fails when caller doesn't own the item
#[test(should_fail_with = "Artifact not found when calling private function")]
unconstrained fn burn_private_not_owner_fail() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    env.advance_block_by(1);

    env.impersonate(recipient);
    SFT::at(sft_contract_address).burn_private(owner, utils::token_id_1, 0).call(&mut env.private());
}

/// Test burning fails with zero token ID
#[test(should_fail_with = "sft not found in private")]
unconstrained fn burn_private_zero_token_id_fail() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    env.advance_block_by(1);

    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_private(owner, 0, 0).call(&mut env.private());
}

/// Test burning fails for non-existent item
#[test(should_fail_with = "sft not found in private")]
unconstrained fn burn_private_nonexistent_item_fail() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_private(owner, utils::token_id_1, 0).call(&mut env.private());
}