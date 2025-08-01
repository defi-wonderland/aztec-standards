use crate::{test::utils::{self, mint_amount}, Token};
use aztec::test::helpers::authwit as authwit_cheatcodes;

// #[test(should_fail_with = "Artifact not found when enriching public simulation error. Contract address: 0x0000000000000000000000000000000000000000000000000000000000000000.")]
// TODO(https://defi-wonderland.slack.com/archives/C086S2Y2925/p1751922367349379): private --> public execution flow is broken in noir tests. While this should fail in private context, the public context error is currently thrown.
#[test(should_fail_with = "Trying to read from uninitialized PublicImmutable")]
unconstrained fn deposit_private_to_private_exact_without_asset() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (_, asset_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);

    let (env, vault_address, _, _, minter) = utils::setup_with_minter(false);

    // Deposit should fail because the PublicImmutable asset was not initialized
    env.impersonate(owner);
    Token::at(vault_address)
        .deposit_private_to_private_exact(owner, recipient, mint_amount, mint_amount, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test]
unconstrained fn deposit_private_to_private_exact_success() {
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

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let min_shares = deposit_amount;
    Token::at(vault_address)
        .deposit_private_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, min_shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == min_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount);
}

#[test]
unconstrained fn deposit_private_to_private_exact_after_yield() {
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

    // Deposit
    env.impersonate(owner);
    let min_shares: u128 = deposit_amount / 2; // The initial rate, when shares' supply is still 0, is given by the amount of assets held by the vault + 1. Since yield = 1, the rate is 1:2.
    Token::at(vault_address)
        .deposit_private_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, min_shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == min_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount + yield_amount);
}

// #[test]
// TODO: Test is incorrectly failing due to an issue that affects the discovery of partial notes.
// When a partial note is initialized and completed and also a note is added, the partial note is not found.
#[test(should_fail_with = "A partial note's completion log did not result in any notes being found - this should never happen")]
unconstrained fn deposit_private_to_private_exact_request_fewer_shares() {
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

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let min_shares = deposit_amount - 1; // But should receive deposit_amount
    Token::at(vault_address)
        .deposit_private_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, min_shares + 1);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == min_shares + 1, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount);
}

#[test(should_fail_with = "Assertion failed: attempt to subtract with overflow ")]
unconstrained fn deposit_private_to_private_exact_request_too_many_shares() {
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

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let min_shares = deposit_amount + 1;
    Token::at(vault_address)
        .deposit_private_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn deposit_private_to_private_exact_without_asset_approval() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let min_shares = deposit_amount;
    Token::at(vault_address)
        .deposit_private_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn deposit_private_to_private_exact_on_behalf_of_wrong_caller() {
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

    // Deposit
    env.impersonate(recipient);
    // At the first deposit 1 share = 1 asset
    let min_shares = deposit_amount;
    Token::at(vault_address)
        .deposit_private_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test]
unconstrained fn deposit_private_to_private_exact_on_behalf_of_other_success() {
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

    // Authorize the recipient to call deposit_private_to_private_exact
    // At the first deposit 1 share = 1 asset
    let min_shares = deposit_amount;
    let deposit_private_to_private_exact_call_interface = Token::at(vault_address)
        .deposit_private_to_private_exact(owner, recipient, deposit_amount, min_shares, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        deposit_private_to_private_exact_call_interface,
    );

    // Deposit
    env.impersonate(recipient);
    Token::at(vault_address)
        .deposit_private_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, min_shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == min_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount);
}
