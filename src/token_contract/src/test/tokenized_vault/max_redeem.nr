use crate::{test::{tokenized_vault::tokenized_vault_utils, utils::{self, mint_amount}}, Token};

/// NOTE: `max_redeem` returns the maximum amount of shares that can be redeemed from
/// the owner's PUBLIC balance. This does NOT include private balance - private holders
/// must track their own balance. This is a fundamental limitation of the privacy model.

#[test]
unconstrained fn max_redeem_zero_without_shares() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, _asset_address) = utils::setup_with_asset(false);

    // max_redeem should return 0 when owner has no shares
    let max_redeem = env.view_public(Token::at(vault_address).max_redeem(owner));

    assert(max_redeem == 0, "max_redeem should return 0 when owner has no shares");
}

#[test]
unconstrained fn max_redeem_returns_public_balance() {
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

    // At first deposit, 1 share = 1 asset
    let expected_shares: u128 = deposit_amount;

    // max_redeem should return the owner's public share balance
    let max_redeem = env.view_public(Token::at(vault_address).max_redeem(owner));

    assert(max_redeem == expected_shares, "max_redeem should return owner's public balance");
}

#[test]
unconstrained fn max_redeem_different_per_owner() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Owner deposits to get shares
    let owner_deposit: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        owner_deposit,
    );

    // Recipient deposits a different amount
    let recipient_deposit: u128 = mint_amount / 2;
    env.call_public(owner, Token::at(asset_address).mint_to_public(recipient, recipient_deposit));
    utils::authorize_transfer_public_to_public(
        env,
        asset_address,
        vault_address,
        recipient,
        recipient_deposit,
        0,
    );
    env.call_public(
        recipient,
        Token::at(vault_address).deposit_public_to_public(
            recipient,
            recipient,
            recipient_deposit,
            0,
        ),
    );

    // max_redeem should return different values for different owners
    let max_redeem_owner = env.view_public(Token::at(vault_address).max_redeem(owner));
    let max_redeem_recipient = env.view_public(Token::at(vault_address).max_redeem(recipient));

    // First deposit 1:1, second deposit also ~1:1 (slight difference due to offset)
    assert(max_redeem_owner == owner_deposit, "max_redeem should return owner's balance");
    assert(max_redeem_recipient > 0, "max_redeem should return recipient's balance");
    assert(
        max_redeem_owner != max_redeem_recipient,
        "Different owners should have different max_redeem",
    );
}

#[test]
unconstrained fn max_redeem_updates_after_redemption() {
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

    // Check initial max_redeem
    let initial_max_redeem = env.view_public(Token::at(vault_address).max_redeem(owner));
    assert(initial_max_redeem == deposit_amount, "Initial max_redeem incorrect");

    // Redeem half the shares
    let redeem_amount: u128 = deposit_amount / 2;
    env.call_public(
        owner,
        Token::at(vault_address).redeem_public_to_public(owner, recipient, redeem_amount, 0),
    );

    // max_redeem should be reduced
    let final_max_redeem = env.view_public(Token::at(vault_address).max_redeem(owner));
    let expected_remaining: u128 = deposit_amount - redeem_amount;

    assert(final_max_redeem == expected_remaining, "max_redeem should decrease after redemption");
}

#[test]
unconstrained fn max_redeem_zero_with_only_private_balance() {
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

    // max_redeem should return 0 because it only reads PUBLIC balance
    let max_redeem = env.view_public(Token::at(vault_address).max_redeem(owner));

    assert(max_redeem == 0, "max_redeem should return 0 when owner only has private balance");
}
