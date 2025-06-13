use crate::{test::utils, Token};
use authwit::cheatcodes as authwit_cheatcodes;

#[test(should_fail_with = "Artifact not found when enriching public simulation error. Contract address: 0x0000000000000000000000000000000000000000000000000000000000000000.")]
unconstrained fn deposit_public_to_public_without_asset() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (_, asset_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_public_without_minter(false);
    
    let (env, vault_address, _, _, minter) = utils::setup_with_minter(false);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface = Token::at(asset_address)
        .transfer_public_to_public(owner, vault_address, mint_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit should fail because the PublicImmutable asset was not initialized
    env.impersonate(owner);
    Token::at(vault_address).deposit_public_to_public(owner, recipient, mint_amount, 0).call(&mut env.public());
    env.advance_block_by(1);
}

#[test]
unconstrained fn deposit_public_to_public_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = 10_000;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(owner, deposit_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface = Token::at(asset_address)
        .transfer_public_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit
    env.impersonate(owner);
    Token::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0).call(&mut env.public());
    env.advance_block_by(1);

    // Check recipient got shares
    // At the first deposit 1 share = 1 asset
    utils::check_public_balance(vault_address, recipient, deposit_amount);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == deposit_amount, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount);
}

#[test]
unconstrained fn deposit_public_to_public_after_yield() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to the vault contract
    let yield_amount: u128 = 1;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(vault_address, yield_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = 10_000;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(owner, deposit_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface = Token::at(asset_address)
        .transfer_public_to_public(owner, vault_address, deposit_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit
    env.impersonate(owner);
    Token::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0).call(&mut env.public());
    env.advance_block_by(1);

    // Check recipient got shares
    let expected_shares: u128 = 5_000; // 10_000 / 2
    utils::check_public_balance(vault_address, recipient, expected_shares);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == expected_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, deposit_amount + yield_amount);
}
