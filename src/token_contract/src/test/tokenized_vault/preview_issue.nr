use crate::{test::utils::{self, mint_amount}, Token};

/// NOTE: We only test `preview_issue` with one issue variant (issue_public_to_public)
/// because `preview_issue` is a pure view function that calculates assets based solely on
/// the vault's current state (total_assets, total_supply). The calculation is independent
/// of the issue mechanism - all issue functions (public -> public, private -> private, etc.)
/// use the same underlying `_convert_to_assets` formula. Therefore, testing with one
/// issue variant is sufficient to verify the preview accuracy.

#[test]
unconstrained fn issue_public_to_public_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to owner
    let max_assets: u128 = mint_amount;
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, max_assets));

    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_public_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        max_assets,
        0,
    );

    // At the first issue 1 share = 1 asset
    let requested_shares: u128 = max_assets;

    // Preview issue before issue
    let preview_issue_assets =
        env.view_public(Token::at(vault_address).preview_issue(requested_shares));

    // Issue
    env.call_public(
        owner,
        Token::at(vault_address).issue_public_to_public(
            owner,
            recipient,
            requested_shares,
            max_assets,
            0,
        ),
    );

    // Check recipient got shares
    // At the first deposit 1 share = 1 asset
    let expected_assets: u128 = max_assets;
    utils::check_public_balance(env, vault_address, recipient, requested_shares);

    // Assert preview issue is correct
    assert(preview_issue_assets == expected_assets, "Incorrect preview issue");
}

#[test]
unconstrained fn preview_issue_with_yield_accrued_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to the vault contract
    let yield_amount: u128 = 1;
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // Mint some asset tokens to owner
    let max_assets: u128 = mint_amount;
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, max_assets));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_public_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        max_assets,
        0,
    );

    let requested_shares: u128 = max_assets / 2; // The initial rate, when shares' supply is still 0, is given by the amount of assets held by the vault + 1. Since yield = 1, the rate is 1:2.

    // Preview issue before issue
    let preview_issue_assets =
        env.view_public(Token::at(vault_address).preview_issue(requested_shares));

    // Issue shares
    env.call_public(
        owner,
        Token::at(vault_address).issue_public_to_public(
            owner,
            recipient,
            requested_shares,
            max_assets,
            0,
        ),
    );

    // Assert preview issue is correct
    assert(preview_issue_assets == max_assets, "Incorrect preview issue");
}

#[test]
unconstrained fn preview_issue_zero_amount() {
    // Setup with asset token
    let (env, vault_address, _owner, _recipient, _asset_address) = utils::setup_with_asset(false);

    // Preview issue with zero shares
    let preview_issue_assets = env.view_public(Token::at(vault_address).preview_issue(0));

    // Zero shares should require zero assets
    assert(preview_issue_assets == 0, "Zero shares should return zero assets");
}
