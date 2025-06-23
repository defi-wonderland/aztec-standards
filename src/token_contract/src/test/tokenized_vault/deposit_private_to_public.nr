use crate::{test::utils::{self, mint_amount}, Token};
use authwit::cheatcodes as authwit_cheatcodes;

#[test(should_fail_with = "Artifact not found when enriching public simulation error. Contract address: 0x0000000000000000000000000000000000000000000000000000000000000000.")]
unconstrained fn deposit_private_to_public_without_asset() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (_, asset_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);

    let (env, vault_address, _, _, minter) = utils::setup_with_minter(true);

    // Deposit should fail because the PublicImmutable asset was not initialized
    env.impersonate(owner);
    Token::at(vault_address).deposit_private_to_public(owner, recipient, mint_amount, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);
}

#[test]
unconstrained fn deposit_private_to_public_success() {
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
    Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Check recipient got shares
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    utils::check_public_balance(vault_address, recipient, shares);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount);
}

#[test]
unconstrained fn deposit_private_to_public_after_yield() {
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
    Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Check recipient got shares
    let expected_shares: u128 = 5_000; // 10_000 / 2 because of yield
    utils::check_public_balance(vault_address, recipient, expected_shares);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == expected_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount + yield_amount);
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn deposit_private_to_public_without_approval() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = 10_000;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit
    env.impersonate(owner);
    Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn deposit_private_to_public_on_behalf_of_wrong_caller() {
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
    Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);
}

#[test]
unconstrained fn deposit_private_to_public_on_behalf_of_other_success() {
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

    // Authorize the recipient to call deposit_private_to_public
    let deposit_private_to_public_call_interface =
        Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        deposit_private_to_public_call_interface,
    );

    // Deposit
    env.impersonate(recipient);
    Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Check recipient got shares
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    utils::check_public_balance(vault_address, recipient, shares);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount);
}
