use crate::{test::{tokenized_vault::tokenized_vault_utils, utils::{self, mint_amount}}, Token};

#[test]
unconstrained fn convert_to_assets_initial_ratio() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, asset_address) = utils::setup_with_asset(false);

    // Mint and deposit assets
    let deposit_amount: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // At initial 1:1 ratio, convert_to_assets should return the same amount
    let shares_to_convert: u128 = 1000;
    let assets = env.view_public(Token::at(vault_address).convert_to_assets(shares_to_convert));

    assert(assets == shares_to_convert, "convert_to_assets should return 1:1 at initial ratio");
}

#[test]
unconstrained fn convert_to_assets_zero_amount() {
    // Setup with asset token
    let (env, vault_address, _owner, _recipient, _asset_address) = utils::setup_with_asset(false);

    // Zero shares should return zero assets
    let assets = env.view_public(Token::at(vault_address).convert_to_assets(0));

    assert(assets == 0, "Zero shares should convert to zero assets");
}

#[test]
unconstrained fn convert_to_assets_with_yield_accrued_rounds_down() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, asset_address) = utils::setup_with_asset(false);

    // Mint and deposit assets
    let deposit_amount: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Simulate yield by minting additional assets directly to the vault
    let yield_amount: u128 = mint_amount;
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // After yield (2x assets), 1000 shares should convert to 1999 assets
    let shares_to_convert: u128 = 1000;
    let expected_assets: u128 = 1999;
    let assets = env.view_public(Token::at(vault_address).convert_to_assets(shares_to_convert));

    assert(assets == expected_assets, "1000 shares should convert to 1999 assets");
}
