use crate::{test::utils::{self, mint_amount}, TokenizedVault};
use token_contract::Token;

#[test]
unconstrained fn total_assets_zero_initially() {
    // Setup with asset token
    let (env, vault_address, _owner, _recipient, _asset_address, _shares_address) =
        utils::setup_with_vault(false);

    // total_assets should be zero before any deposits
    let total_assets = env.view_public(TokenizedVault::at(vault_address).total_assets());

    assert(total_assets == 0, "total_assets should be zero initially");
}

#[test]
unconstrained fn total_assets_after_deposit() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, asset_address, shares_address) =
        utils::setup_with_vault(false);

    // Mint and deposit assets
    let deposit_amount: u128 = mint_amount;
    utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        shares_address,
        owner,
        deposit_amount,
    );

    // total_assets should equal the deposited amount
    let total_assets = env.view_public(TokenizedVault::at(vault_address).total_assets());

    assert(total_assets == deposit_amount, "total_assets should equal deposited amount");
}

#[test]
unconstrained fn total_assets_with_yield_accrued() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, asset_address, shares_address) =
        utils::setup_with_vault(false);

    // Mint and deposit assets
    let deposit_amount: u128 = mint_amount;
    utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        shares_address,
        owner,
        deposit_amount,
    );

    // Simulate yield by minting additional assets directly to the vault
    let yield_amount: u128 = 1000;
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // total_assets should include the yield
    let total_assets = env.view_public(TokenizedVault::at(vault_address).total_assets());
    let expected_total = deposit_amount + yield_amount;

    assert(total_assets == expected_total, "total_assets should include yield");
}
