use crate::{test::utils::{self, mint_amount}, Token};
use authwit::cheatcodes as authwit_cheatcodes;

#[test(should_fail_with = "Artifact not found when enriching public simulation error. Contract address: 0x0000000000000000000000000000000000000000000000000000000000000000.")]
unconstrained fn deposit_private_to_private_without_asset() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (_, asset_address, owner, recipient) = utils::setup_and_mint_to_public_without_minter(true);

    let (env, vault_address, _, _, minter) = utils::setup_with_minter(true);

    // Deposit should fail because the PublicImmutable asset was not initialized
    env.impersonate(owner);
    Token::at(vault_address)
        .deposit_private_to_private(owner, recipient, mint_amount, mint_amount, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test]
unconstrained fn deposit_private_to_private_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = 10_000;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let transfer_private_to_public_call_interface = Token::at(asset_address)
        .transfer_private_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        vault_address,
        transfer_private_to_public_call_interface,
    );

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    Token::at(vault_address)
        .deposit_private_to_private(owner, recipient, deposit_amount, shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount);
}

#[test]
unconstrained fn deposit_private_to_private_after_yield() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to the vault contract
    let yield_amount: u128 = 1;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(vault_address, yield_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = 10_000;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let transfer_private_to_public_call_interface = Token::at(asset_address)
        .transfer_private_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        vault_address,
        transfer_private_to_public_call_interface,
    );

    // Deposit
    env.impersonate(owner);
    let expected_shares: u128 = 5_000; // 10_000 / 2 because of yield
    Token::at(vault_address)
        .deposit_private_to_private(owner, recipient, deposit_amount, expected_shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, expected_shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == expected_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount + yield_amount);
}

#[test]
unconstrained fn deposit_private_to_private_request_fewer_shares() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = 10_000;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let transfer_private_to_public_call_interface = Token::at(asset_address)
        .transfer_private_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        vault_address,
        transfer_private_to_public_call_interface,
    );

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let shares = 9_999;
    Token::at(vault_address)
        .deposit_private_to_private(owner, recipient, deposit_amount, shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount);
}

#[test(should_fail_with = "Too many shares requested")]
unconstrained fn deposit_private_to_private_request_too_many_shares() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = 10_000;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let transfer_private_to_public_call_interface = Token::at(asset_address)
        .transfer_private_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        vault_address,
        transfer_private_to_public_call_interface,
    );

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount + 1;
    Token::at(vault_address)
        .deposit_private_to_private(owner, recipient, deposit_amount, shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

// Unknown auth witness for message hash 0x232f5ba6edab22c5556f3c3ab5560760cc4e579cb15f1ced71986c45ae9907b2
#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn deposit_private_to_private_without_approval() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = 10_000;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    Token::at(vault_address)
        .deposit_private_to_private(owner, recipient, deposit_amount, shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

// Unknown auth witness for message hash 0x1c41820919d716167dfc607c636bf8066f421d80f001e5ab596f8ddaf07f0760
#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn deposit_private_to_private_on_behalf_of_wrong_caller() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = 10_000;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let transfer_private_to_public_call_interface = Token::at(asset_address)
        .transfer_private_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        vault_address,
        transfer_private_to_public_call_interface,
    );

    // Deposit
    env.impersonate(recipient);
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    Token::at(vault_address)
        .deposit_private_to_private(owner, recipient, deposit_amount, shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test]
unconstrained fn deposit_private_to_private_on_behalf_of_other_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = 10_000;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let transfer_private_to_public_call_interface = Token::at(asset_address)
        .transfer_private_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        vault_address,
        transfer_private_to_public_call_interface,
    );

    // Authorize the recipient to call deposit_private_to_private
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    let deposit_private_to_private_call_interface = Token::at(vault_address)
        .deposit_private_to_private(owner, recipient, deposit_amount, shares, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        deposit_private_to_private_call_interface,
    );

    // Deposit
    env.impersonate(recipient);
    Token::at(vault_address)
        .deposit_private_to_private(owner, recipient, deposit_amount, shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount);
}
