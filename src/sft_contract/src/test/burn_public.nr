use crate::SFT;
use crate::test::utils;

/// Test successful public burning
#[test]
unconstrained fn burn_public_success() {
    let (env, sft_contract_address, owner, _, _) = utils::setup_and_mint_to_public(false);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 2);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 2);

    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_public(owner, utils::token_id_1, 0).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 1);
}

/// Test burning is isolated per token type
#[test]
unconstrained fn burn_public_separate_token_types_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.impersonate(minter);
    SFT::at(sft_contract_address).create_token_type(utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).create_token_type(utils::token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 2);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_2, 1);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 2);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_2, 1);

    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_public(owner, utils::token_id_1, 0).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_2, 1);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 1);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_2, 1);
}

/// Test burning is isolated per owner
#[test]
unconstrained fn burn_public_separate_owners_success() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);

    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(recipient, utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(recipient, utils::token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_public(owner, utils::token_id_1, 0).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 0);
    utils::check_public_balance(env, sft_contract_address, recipient, utils::token_id_1, 2);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 2);
}

/// Test burning fails when caller doesn't own the item
#[test(should_fail_with = "unauthorized")]
unconstrained fn burn_public_not_owner_fail() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    env.impersonate(recipient);
    SFT::at(sft_contract_address).burn_public(owner, utils::token_id_1, 0).call(&mut env.public());
}

/// Test burning fails with zero token ID
#[test(should_fail_with = "caller owns no tokens of this type")]
unconstrained fn burn_public_zero_token_id_fail() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_public(owner, 0, 0).call(&mut env.public());
}

/// Test burning fails for non-existent item
#[test(should_fail_with = "caller owns no tokens of this type")]
unconstrained fn burn_public_nonexistent_item_fail() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(owner);
    SFT::at(sft_contract_address).burn_public(owner, utils::token_id_1, 0).call(&mut env.public());
}