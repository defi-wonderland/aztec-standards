use crate::{test::{tokenized_vault::tokenized_vault_utils, utils::{self, mint_amount}}, Token};

#[test]
unconstrained fn convert_to_shares_initial_ratio() {
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

    // At initial 1:1 ratio, convertToShares should return the same amount
    let assets_to_convert: u128 = 1000;
    let shares = env.view_public(Token::at(vault_address).convertToShares(assets_to_convert));

    assert(shares == assets_to_convert, "convertToShares should return 1:1 at initial ratio");
}

#[test]
unconstrained fn convert_to_shares_zero_amount() {
    // Setup with asset token
    let (env, vault_address, _owner, _recipient, _asset_address) = utils::setup_with_asset(false);

    // Zero assets should return zero shares
    let shares = env.view_public(Token::at(vault_address).convertToShares(0));

    assert(shares == 0, "Zero assets should convert to zero shares");
}

#[test]
unconstrained fn convert_to_shares_with_yield_accrued() {
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

    // After yield, 1 share should be worth 2 assets
    let assets_to_convert: u128 = 2000;
    let shares = env.view_public(Token::at(vault_address).convertToShares(assets_to_convert));

    assert(shares < assets_to_convert, "After yield, fewer shares per asset");
}
