use crate::{test::{tokenized_vault::tokenized_vault_utils, utils::{self, mint_amount}}, Token};

/// NOTE: We only test `preview_redeem` with one redeem variant (redeem_public_to_public)
/// because `preview_redeem` is a pure view function that calculates shares based solely on
/// the vault's current state (total_assets, total_supply). The calculation is independent
/// of the redeem mechanism - all redeem functions (public -> public, private -> private, etc.)
/// use the same underlying `_convert_to_shares` formula. Therefore, testing with one
/// redeem variant is sufficient to verify the preview accuracy.

#[test]
unconstrained fn preview_redeem_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint and deposit assets to get shares
    let deposit_amount: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // At first deposit, 1 share = 1 asset
    let assets_to_redeem: u128 = deposit_amount;

    // Preview redeem before redeem
    let preview_redeem_shares =
        env.view_public(Token::at(vault_address).preview_redeem(assets_to_redeem));

    // Redeem
    let shares_to_burn: u128 = deposit_amount;
    env.call_public(
        owner,
        Token::at(vault_address).redeem_public_to_public(owner, recipient, shares_to_burn, 0),
    );

    // Check recipient received assets (1:1 ratio)
    utils::check_public_balance(env, asset_address, recipient, assets_to_redeem);

    // Assert preview redeem is correct (1:1 ratio)
    let expected_shares: u128 = assets_to_redeem;
    assert(preview_redeem_shares == expected_shares, "Incorrect preview redeem");
}

#[test]
unconstrained fn preview_redeem_with_yield_accrued_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint and deposit assets to get shares
    let deposit_amount: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Mint some asset tokens to the vault contract (simulating yield)
    // Using 2 instead of 1 avoids rounding issues from anti-inflation logic
    let yield_amount: u128 = 2;
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // Redeem all shares
    let shares_to_burn: u128 = deposit_amount;
    let preview_redeem_assets =
        env.view_public(Token::at(vault_address).preview_redeem(shares_to_burn));

    let expected_assets: u128 = deposit_amount + 1;
    assert(
        preview_redeem_assets == expected_assets,
        "preview_redeem should return the expected assets",
    );

    env.call_public(
        owner,
        Token::at(vault_address).redeem_public_to_public(owner, recipient, shares_to_burn, 0),
    );

    // Check recipient received the expected assets
    utils::check_public_balance(env, asset_address, recipient, expected_assets);
}

#[test]
unconstrained fn preview_redeem_zero_amount() {
    // Setup with asset token
    let (env, vault_address, _owner, _recipient, _asset_address) = utils::setup_with_asset(false);

    // Preview redeem with zero assets
    let preview_redeem_shares = env.view_public(Token::at(vault_address).preview_redeem(0));

    // Zero assets should require zero shares
    assert(preview_redeem_shares == 0, "Zero assets should return zero shares");
}
