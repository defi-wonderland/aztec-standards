use crate::{test::{tokenized_vault::tokenized_vault_utils, utils::{self, mint_amount}}, Token};

/// NOTE: We only test `preview_withdraw` with one withdraw variant (withdraw_public_to_public)
/// because `preview_withdraw` is a pure view function that calculates assets based solely on
/// the vault's current state (total_assets, total_supply). The calculation is independent
/// of the withdraw mechanism - all withdraw functions (public -> public, private -> private, etc.)
/// use the same underlying `_convert_to_assets` formula. Therefore, testing with one
/// withdraw variant is sufficient to verify the preview accuracy.

#[test]
unconstrained fn preview_withdraw_success() {
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
    let shares_to_withdraw: u128 = deposit_amount;

    // Preview withdraw before withdraw
    let preview_withdraw_assets =
        env.view_public(Token::at(vault_address).preview_withdraw(shares_to_withdraw));

    // Withdraw
    env.call_public(
        owner,
        Token::at(vault_address).withdraw_public_to_public(owner, recipient, deposit_amount, 0),
    );

    // Check recipient received assets (1:1 ratio)
    let expected_assets: u128 = shares_to_withdraw;
    utils::check_public_balance(env, asset_address, recipient, expected_assets);

    // Assert preview withdraw is correct
    assert(preview_withdraw_assets == expected_assets, "Incorrect preview withdraw");
}

#[test]
unconstrained fn preview_withdraw_with_yield_accrued_success() {
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

    // After yield, each share is worth more assets
    // Total assets = deposit_amount + yield_amount, total shares = deposit_amount
    // Rate = (deposit_amount + yield_amount) / deposit_amount
    let expected_assets_to_withdraw: u128 = deposit_amount + 1;

    // Preview withdraw before withdraw
    let preview_withdraw_shares =
        env.view_public(Token::at(vault_address).preview_withdraw(expected_assets_to_withdraw));

    // Withdraw all shares
    let expected_shares_to_burn: u128 = deposit_amount;
    assert(
        preview_withdraw_shares == expected_shares_to_burn,
        "preview_withdraw should return the expected shares",
    );

    // Withdraw
    env.call_public(
        owner,
        Token::at(vault_address).withdraw_public_to_public(
            owner,
            recipient,
            expected_assets_to_withdraw,
            0,
        ),
    );

    // Check recipient received assets
    utils::check_public_balance(env, asset_address, recipient, expected_assets_to_withdraw);
}

#[test]
unconstrained fn preview_withdraw_zero_amount() {
    // Setup with asset token
    let (env, vault_address, _owner, _recipient, _asset_address) = utils::setup_with_asset(false);

    // Preview withdraw with zero shares
    let preview_withdraw_assets = env.view_public(Token::at(vault_address).preview_withdraw(0));

    // Zero shares should yield zero assets
    assert(preview_withdraw_assets == 0, "Zero shares should return zero assets");
}
