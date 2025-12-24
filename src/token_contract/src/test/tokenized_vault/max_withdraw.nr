use crate::{test::{tokenized_vault::tokenized_vault_utils, utils::{self, mint_amount}}, Token};

/// NOTE: `max_withdraw` returns the maximum amount of assets that can be withdrawn from
/// the owner's PUBLIC balance. This does NOT include private balance - private holders
/// must track their own balance. It is calculated as previewWithdraw(max_redeem(owner)).

#[test]
unconstrained fn max_withdraw_zero_without_shares() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, _asset_address) = utils::setup_with_asset(false);

    // max_withdraw should return 0 when owner has no shares
    let max_withdraw = env.view_public(Token::at(vault_address).max_withdraw(owner));

    assert(max_withdraw == 0, "max_withdraw should return 0 when owner has no shares");
}

#[test]
unconstrained fn max_withdraw_returns_asset_equivalent() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, asset_address) = utils::setup_with_asset(false);

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

    // At first deposit, 1 share = 1 asset, so max_withdraw should equal deposit_amount
    let max_withdraw = env.view_public(Token::at(vault_address).max_withdraw(owner));

    assert(max_withdraw == deposit_amount, "max_withdraw should return asset equivalent of shares");
}

#[test]
unconstrained fn max_withdraw_increases_with_yield() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, asset_address) = utils::setup_with_asset(false);

    // Deposit to get shares
    let deposit_amount: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Check initial max_withdraw
    let initial_max_withdraw = env.view_public(Token::at(vault_address).max_withdraw(owner));

    // Add yield to the vault
    let yield_amount: u128 = mint_amount; // Double the assets
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // max_withdraw should increase because each share is now worth more assets
    let final_max_withdraw = env.view_public(Token::at(vault_address).max_withdraw(owner));

    assert(final_max_withdraw > initial_max_withdraw, "max_withdraw should increase after yield");
}

#[test]
unconstrained fn max_withdraw_equals_preview_of_max_redeem() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, asset_address) = utils::setup_with_asset(false);

    // Deposit to get shares
    let deposit_amount: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Add some yield to make it interesting
    let yield_amount: u128 = 100;
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // Get max_redeem and previewWithdraw separately
    let max_redeem = env.view_public(Token::at(vault_address).max_redeem(owner));
    let preview_redeem_assets =
        env.view_public(Token::at(vault_address).preview_redeem(max_redeem));

    let max_withdraw_assets = env.view_public(Token::at(vault_address).max_withdraw(owner));

    assert(
        max_withdraw_assets == preview_redeem_assets,
        "max_withdraw should equal preview_redeem(max_redeem)",
    );
}

#[test]
unconstrained fn max_withdraw_updates_after_withdrawal() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Deposit to get shares
    let deposit_amount: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Check initial max_withdraw
    let initial_max_withdraw = env.view_public(Token::at(vault_address).max_withdraw(owner));

    // Withdraw half the assets
    let withdraw_amount: u128 = deposit_amount / 2;
    env.call_public(
        owner,
        Token::at(vault_address).withdraw_public_to_public(owner, recipient, withdraw_amount, 0),
    );

    // max_withdraw should be reduced
    let final_max_withdraw = env.view_public(Token::at(vault_address).max_withdraw(owner));

    assert(
        final_max_withdraw < initial_max_withdraw,
        "max_withdraw should decrease after withdrawal",
    );
}

#[test]
unconstrained fn max_withdraw_zero_with_only_private_balance() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, asset_address) = utils::setup_with_asset(false);

    // Deposit to PRIVATE balance using the helper
    let deposit_amount: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_private(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Verify owner has private balance
    utils::check_private_balance(env, vault_address, owner, deposit_amount);

    // max_withdraw should return 0 because it only reads PUBLIC balance
    let max_withdraw = env.view_public(Token::at(vault_address).max_withdraw(owner));

    assert(max_withdraw == 0, "max_withdraw should return 0 when owner only has private balance");
}
