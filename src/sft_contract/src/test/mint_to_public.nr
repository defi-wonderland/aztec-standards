use crate::SFT;
use crate::test::utils;

/// Test successful public minting
#[test]
unconstrained fn mint_to_public_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
}

/// Test that public balance increases after multiple mints
#[test]
unconstrained fn public_balance_increases_after_minting_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 2);
}

/// Test that total supply increases after public minting
#[test]
unconstrained fn total_supply_increases_after_public_minting_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);
    
    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 2);
}

/// Test that balances are separate for different token types
#[test]
unconstrained fn mint_to_public_separate_token_types_success() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.impersonate(minter);
    SFT::at(sft_contract_address).create_token_type(utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).create_token_type(utils::token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_2).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_2, 2);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_1, 1);
    utils::check_total_supply(env, sft_contract_address, utils::token_id_2, 2);
}

/// Test that balances are separate for different owners
#[test]
unconstrained fn mint_to_public_separate_owners_success() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);

    utils::create_test_token_type(env, sft_contract_address, minter);

    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(recipient, utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).mint_to_public(recipient, utils::token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_public_balance(env, sft_contract_address, recipient, utils::token_id_1, 2);
}

/// Test minting fails without minter role
#[test(should_fail_with = "caller is not minter")]
unconstrained fn mint_to_public_not_minter_fail() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);

    env.impersonate(recipient);
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
}

/// Test minting fails for non-existent token type
#[test(should_fail_with = "token type does not exist")]
unconstrained fn mint_to_public_token_type_does_not_exist_fail() {
    let (env, sft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_public(owner, utils::token_id_1).call(&mut env.public());
}
