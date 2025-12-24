use crate::{test::utils::{self, mint_amount}, Token};

/// NOTE: We only test `preview_deposit` with one deposit variant (deposit_public_to_public)
/// because `preview_deposit` is a pure view function that calculates shares based solely on
/// the vault's current state (total_assets, total_supply). The calculation is independent
/// of the deposit mechanism - all deposit functions (public -> public, private -> private, etc.)
/// use the same underlying `_convert_to_shares` formula. Therefore, testing with one
/// deposit variant is sufficient to verify the preview accuracy.

#[test]
unconstrained fn preview_deposit_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_public_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Preview deposit before deposit
    let preview_deposit_shares =
        env.view_public(Token::at(vault_address).preview_deposit(deposit_amount));

    // Deposit
    env.call_public(
        owner,
        Token::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0),
    );

    // Check recipient got shares
    // At the first deposit 1 share = 1 asset
    let expected_shares: u128 = deposit_amount;
    utils::check_public_balance(env, vault_address, recipient, expected_shares);

    // Assert preview deposit is correct
    assert(preview_deposit_shares == expected_shares, "Incorrect preview deposit");
}

#[test]
unconstrained fn preview_deposit_with_yield_accrued_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to the vault contract
    let yield_amount: u128 = 1;
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_public_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Preview deposit before deposit
    let preview_deposit_shares =
        env.view_public(Token::at(vault_address).preview_deposit(deposit_amount));

    // Deposit
    env.call_public(
        owner,
        Token::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0),
    );

    // Check recipient got shares
    let expected_shares: u128 = deposit_amount / 2; // The initial rate, when shares' supply is still 0, is given by the amount of assets held by the vault + 1. Since yield = 1, the rate is 1:2.
    utils::check_public_balance(env, vault_address, recipient, expected_shares);

    // Assert preview deposit is correct
    assert(preview_deposit_shares == expected_shares, "Incorrect preview deposit");
}

#[test]
unconstrained fn preview_deposit_zero_amount() {
    // Setup with asset token
    let (env, vault_address, _owner, _recipient, _asset_address) = utils::setup_with_asset(false);

    // Preview deposit with zero assets
    let preview_deposit_shares = env.view_public(Token::at(vault_address).preview_deposit(0));

    // Zero assets should yield zero shares
    assert(preview_deposit_shares == 0, "Zero assets should return zero shares");
}
