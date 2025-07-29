use crate::{test::utils::{self, mint_amount}, Token};
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test(should_fail_with = "Artifact not found when calling private function. Contract address: 0x0000000000000000000000000000000000000000000000000000000000000000.")]
unconstrained fn issue_private_to_private_exact_without_asset() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (_, asset_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);

    let (env, vault_address, _, _, minter) = utils::setup_with_minter(true);

    // Issue should fail because the PublicImmutable asset was not initialized
    env.impersonate(owner);
    Token::at(vault_address)
        .issue_private_to_private_exact(owner, recipient, mint_amount, mint_amount, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test]
unconstrained fn issue_private_to_private_exact_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Issue shares
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let max_assets = deposit_amount;
    let requested_shares = deposit_amount;
    Token::at(vault_address)
        .issue_private_to_private_exact(owner, recipient, requested_shares, max_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, requested_shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == requested_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, max_assets);
}

#[test]
unconstrained fn issue_private_to_private_exact_after_yield() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to the vault contract
    let yield_amount: u128 = 1;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(vault_address, yield_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Issue shares
    env.impersonate(owner);
    let max_assets: u128 = deposit_amount;
    let requested_shares = deposit_amount / 2; // The initial rate, when shares' supply is still 0, is given by the amount of assets held by the vault + 1. Since yield = 1, the rate is 1:2.
    Token::at(vault_address)
        .issue_private_to_private_exact(owner, recipient, requested_shares, max_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, requested_shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == requested_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, max_assets + yield_amount);
}

// TODO: Test is incorrectly failing due to an issue that affects the discovery of partial notes.
// When a partial note is initialized and completed and also a note is added, the partial note is not found.
#[test(should_fail_with = "A partial note's completion log did not result in any notes being found - this should never happen")]
unconstrained fn issue_private_to_private_exact_too_many_assets() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let max_deposit: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, max_deposit).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        asset_address,
        vault_address,
        owner,
        max_deposit,
        0,
    );

    // Issue shares
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let requested_shares = max_deposit - 1; // But should receive deposit_amount
    Token::at(vault_address)
        .issue_private_to_private_exact(owner, recipient, requested_shares, max_deposit, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, requested_shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == requested_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, requested_shares);
    utils::check_private_balance(asset_address, owner, 1);
}

#[test(should_fail_with = "Assertion failed: attempt to subtract with overflow ")]
unconstrained fn issue_private_to_private_exact_request_too_many_shares() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Issue shares
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let max_assets = deposit_amount;
    let requested_shares = deposit_amount + 1;
    Token::at(vault_address)
        .issue_private_to_private_exact(owner, recipient, requested_shares, max_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn issue_private_to_private_exact_without_asset_approval() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Issue shares
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let max_assets = deposit_amount;
    Token::at(vault_address)
        .issue_private_to_private_exact(owner, recipient, deposit_amount, max_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn issue_private_to_private_exact_on_behalf_of_wrong_caller() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Issue shares
    env.impersonate(recipient);
    // At the first deposit 1 share = 1 asset
    let max_assets = deposit_amount;
    Token::at(vault_address)
        .issue_private_to_private_exact(owner, recipient, deposit_amount, max_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test]
unconstrained fn issue_private_to_private_exact_on_behalf_of_other_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Authorize the recipient to call issue_private_to_private_exact
    // At the first deposit 1 share = 1 asset
    let max_assets = deposit_amount;
    let requested_shares = deposit_amount;
    let issue_private_to_private_exact_call_interface = Token::at(vault_address)
        .issue_private_to_private_exact(owner, recipient, requested_shares, max_assets, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        issue_private_to_private_exact_call_interface,
    );

    // Issue shares
    env.impersonate(recipient);
    Token::at(vault_address)
        .issue_private_to_private_exact(owner, recipient, requested_shares, max_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, requested_shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == requested_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, max_assets);
}
