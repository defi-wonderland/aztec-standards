use crate::{test::utils::{self, mint_amount}, Token};
use authwit::cheatcodes as authwit_cheatcodes;

#[test(should_fail_with = "Artifact not found when enriching public simulation error. Contract address: 0x0000000000000000000000000000000000000000000000000000000000000000.")]
unconstrained fn deposit_public_to_private_exact_without_asset() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (_, asset_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);

    let (env, vault_address, _, _, minter) = utils::setup_with_minter(false);

    // Deposit should fail because the PublicImmutable asset was not initialized
    env.impersonate(owner);
    Token::at(vault_address)
        .deposit_public_to_private_exact(owner, recipient, mint_amount, mint_amount, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test]
unconstrained fn deposit_public_to_private_exact_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(owner, deposit_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface =
        Token::at(asset_address).transfer_public_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let min_shares = deposit_amount;
    Token::at(vault_address)
        .deposit_public_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
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
unconstrained fn deposit_public_to_private_exact_after_yield() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to the vault contract
    let yield_amount: u128 = 1;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(vault_address, yield_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(owner, deposit_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface =
        Token::at(asset_address).transfer_public_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit
    env.impersonate(owner);
    let min_shares: u128 = 5_000; // mint_amount / 2 because of yield
    Token::at(vault_address)
        .deposit_public_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
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
#[test(should_fail_with = "Assertion failed: Private balance is not correct")]
unconstrained fn deposit_public_to_private_exact_request_fewer_shares() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(owner, deposit_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface =
        Token::at(asset_address).transfer_public_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let min_shares = 9_999; // But should receive 10_000
    Token::at(vault_address)
        .deposit_public_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
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
unconstrained fn deposit_public_to_private_exact_request_too_many_shares() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(owner, deposit_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface =
        Token::at(asset_address).transfer_public_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let min_shares = deposit_amount + 1;
    Token::at(vault_address)
        .deposit_public_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn deposit_public_to_private_exact_without_approval() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(owner, deposit_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let min_shares = deposit_amount;
    Token::at(vault_address)
        .deposit_public_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn deposit_public_to_private_exact_on_behalf_of_wrong_caller() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(owner, deposit_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface =
        Token::at(asset_address).transfer_public_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit
    env.impersonate(recipient);
    // At the first deposit 1 share = 1 asset
    let min_shares = deposit_amount;
    Token::at(vault_address)
        .deposit_public_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test]
unconstrained fn deposit_public_to_private_exact_on_behalf_of_other_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(owner, deposit_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface =
        Token::at(asset_address).transfer_public_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Authorize the recipient to call deposit_public_to_private_exact
    // At the first deposit 1 share = 1 asset
    let min_shares = deposit_amount;
    let deposit_public_to_private_exact_call_interface = Token::at(vault_address)
        .deposit_public_to_private_exact(owner, recipient, deposit_amount, min_shares, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        deposit_public_to_private_exact_call_interface,
    );

    // Deposit
    env.impersonate(recipient);
    Token::at(vault_address)
        .deposit_public_to_private_exact(owner, recipient, deposit_amount, min_shares, 0)
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
