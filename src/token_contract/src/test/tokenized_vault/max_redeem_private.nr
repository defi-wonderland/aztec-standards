use crate::{test::{tokenized_vault::tokenized_vault_utils, utils::{self, mint_amount}}, Token};

/// NOTE: `max_redeem_private` returns the maximum amount of shares that can be redeemed from
/// the owner's PRIVATE balance only. Use `max_redeem` for public balance.

#[test]
unconstrained fn max_redeem_private_zero_without_shares() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, _asset_address) = utils::setup_with_asset(false);

    // max_redeem_private should return 0 when owner has no shares
    let max_redeem_private =
        env.simulate_utility(Token::at(vault_address).max_redeem_private(owner));

    assert(max_redeem_private == 0, "max_redeem_private should return 0 when owner has no shares");
}

#[test]
unconstrained fn max_redeem_private_zero_with_only_public_balance() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, asset_address) = utils::setup_with_asset(false);

    // Mint and deposit assets to get PUBLIC shares
    let deposit_amount: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // max_redeem_private should return 0 when owner only has public shares
    let max_redeem_private =
        env.simulate_utility(Token::at(vault_address).max_redeem_private(owner));

    assert(max_redeem_private == 0, "max_redeem_private should return 0 when only public exists");

    // Compare with max_redeem (public only) which should have the balance
    let max_redeem_public = env.view_public(Token::at(vault_address).max_redeem(owner));
    assert(max_redeem_public == deposit_amount, "max_redeem should return public balance");
}

#[test]
unconstrained fn max_redeem_private_returns_private_balance() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, asset_address) = utils::setup_with_asset(false);

    // Mint and deposit assets to get PRIVATE shares
    let deposit_amount: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_private(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // At first deposit, 1 share = 1 asset
    let expected_shares: u128 = deposit_amount;

    // max_redeem_private should return the owner's private share balance
    let max_redeem_private =
        env.simulate_utility(Token::at(vault_address).max_redeem_private(owner));

    assert(
        max_redeem_private == expected_shares,
        "max_redeem_private should return private balance",
    );

    // Compare with max_redeem (public only) which should be 0
    let max_redeem_public = env.view_public(Token::at(vault_address).max_redeem(owner));
    assert(max_redeem_public == 0, "max_redeem should return 0 for private-only balance");
}

#[test]
unconstrained fn max_redeem_private_only_returns_private_when_both_exist() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, asset_address) = utils::setup_with_asset(false);

    // Deposit to PUBLIC shares first
    let public_deposit: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        public_deposit,
    );

    // Deposit to PRIVATE shares
    let private_deposit: u128 = mint_amount / 2;
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, private_deposit));
    utils::authorize_transfer_public_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        private_deposit,
        0,
    );
    env.call_private(
        owner,
        Token::at(vault_address).deposit_public_to_private(
            owner,
            owner,
            private_deposit,
            private_deposit,
            0,
        ),
    );

    // max_redeem_private should return ONLY private shares
    let max_redeem_private =
        env.simulate_utility(Token::at(vault_address).max_redeem_private(owner));

    assert(
        max_redeem_private == private_deposit,
        "max_redeem_private should return only private shares",
    );

    // Compare with max_redeem (public only)
    let max_redeem_public = env.view_public(Token::at(vault_address).max_redeem(owner));
    assert(max_redeem_public == public_deposit, "max_redeem should return only public balance");
}

#[test]
unconstrained fn max_redeem_private_different_per_owner() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Owner deposits to private
    let owner_deposit: u128 = mint_amount;
    tokenized_vault_utils::mint_and_deposit_public_to_private(
        env,
        owner,
        asset_address,
        vault_address,
        owner,
        owner_deposit,
    );

    // Recipient deposits to private (different amount)
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
    env.call_private(
        recipient,
        Token::at(vault_address).deposit_public_to_private(
            recipient,
            recipient,
            recipient_deposit,
            recipient_deposit,
            0,
        ),
    );

    // Check max_redeem_private for both
    let owner_max = env.simulate_utility(Token::at(vault_address).max_redeem_private(owner));
    let recipient_max =
        env.simulate_utility(Token::at(vault_address).max_redeem_private(recipient));

    assert(owner_max == owner_deposit, "Owner max_redeem_private incorrect");
    assert(recipient_max == recipient_deposit, "Recipient max_redeem_private incorrect");
    assert(owner_max != recipient_max, "Different owners should have different max_redeem_private");
}
