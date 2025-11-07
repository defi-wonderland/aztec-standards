use crate::{test::utils::{self, mint_amount}, Token};
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test(should_fail_with = "Contract execution has reverted: No bytecode found, or limit encountered for max calls to unique contract class IDs. Contract address: 0x0000000000000000000000000000000000000000000000000000000000000000.")]
unconstrained fn issue_public_to_private_without_asset() {
    let (env, vault_address, owner, recipient, _) = utils::setup_with_minter(false);

    // Issue should fail because the PublicImmutable asset was not initialized
    env.call_private(
        owner,
        Token::at(vault_address).issue_public_to_private(
            owner,
            recipient,
            mint_amount,
            mint_amount,
            0,
        ),
    );
}

#[test]
unconstrained fn issue_public_to_private_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

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

    // Issue shares
    // At the first deposit 1 share = 1 asset
    let requested_shares: u128 = max_assets;
    env.call_private(
        owner,
        Token::at(vault_address).issue_public_to_private(
            owner,
            recipient,
            requested_shares,
            max_assets,
            0,
        ),
    );

    // Check recipient got shares
    utils::check_private_balance(env, vault_address, recipient, requested_shares);
    utils::check_public_balance(env, vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(vault_address).total_supply());
    assert(total_supply == requested_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(env, asset_address, vault_address, max_assets);
}

#[test]
unconstrained fn issue_public_to_private_with_change_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

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

    // Issue shares
    let requested_shares: u128 = max_assets - 1;
    env.call_private(
        owner,
        Token::at(vault_address).issue_public_to_private(
            owner,
            recipient,
            requested_shares,
            max_assets,
            0,
        ),
    );

    // Check recipient got shares
    utils::check_private_balance(env, vault_address, recipient, requested_shares);
    utils::check_public_balance(env, vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(vault_address).total_supply());
    assert(total_supply == requested_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(env, asset_address, vault_address, max_assets - 1);
    utils::check_public_balance(env, asset_address, owner, 1);
}

#[test]
unconstrained fn issue_public_to_private_after_yield() {
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

    // Issue shares
    let expected_shares: u128 = max_assets / 2; // The initial rate, when shares' supply is still 0, is given by the amount of assets held by the vault + 1. Since yield = 1, the rate is 1:2.
    env.call_private(
        owner,
        Token::at(vault_address).issue_public_to_private(
            owner,
            recipient,
            expected_shares,
            max_assets,
            0,
        ),
    );

    // Check recipient got shares
    utils::check_private_balance(env, vault_address, recipient, expected_shares);
    utils::check_public_balance(env, vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(vault_address).total_supply());
    assert(total_supply == expected_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(env, asset_address, vault_address, max_assets + yield_amount);
}

#[test(should_fail_with = "Assertion failed: attempt to subtract with overflow")]
unconstrained fn issue_public_to_private_request_too_many_shares() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

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

    // Issue shares
    // At the first deposit 1 share = 1 asset
    let requested_shares = max_assets + 1;
    env.call_private(
        owner,
        Token::at(vault_address).issue_public_to_private(
            owner,
            recipient,
            requested_shares,
            max_assets,
            0,
        ),
    );
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn issue_public_to_private_without_asset_approval() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let max_assets: u128 = mint_amount;
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, max_assets));

    // Issue shares
    // At the first deposit 1 share = 1 asset
    let requested_shares = max_assets;
    env.call_private(
        owner,
        Token::at(vault_address).issue_public_to_private(
            owner,
            recipient,
            requested_shares,
            max_assets,
            0,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn issue_public_to_private_on_behalf_of_wrong_caller() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

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

    // Issue shares
    // At the first deposit 1 share = 1 asset
    let requested_shares = max_assets;
    env.call_private(
        recipient,
        Token::at(vault_address).issue_public_to_private(
            owner,
            recipient,
            requested_shares,
            max_assets,
            0,
        ),
    );
}

#[test]
unconstrained fn issue_public_to_private_on_behalf_of_other_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

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

    // Authorize the recipient to call issue_public_to_private
    // At the first deposit 1 share = 1 asset
    let requested_shares = max_assets;
    let issue_public_to_private_call_interface = Token::at(vault_address).issue_public_to_private(
        owner,
        recipient,
        requested_shares,
        max_assets,
        0,
    );
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        env,
        owner,
        recipient,
        issue_public_to_private_call_interface,
    );

    // Issue shares
    env.call_private(
        recipient,
        Token::at(vault_address).issue_public_to_private(
            owner,
            recipient,
            requested_shares,
            max_assets,
            0,
        ),
    );

    // Check recipient got shares
    utils::check_private_balance(env, vault_address, recipient, requested_shares);
    utils::check_public_balance(env, vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(vault_address).total_supply());
    assert(total_supply == requested_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(env, asset_address, vault_address, max_assets);
}
