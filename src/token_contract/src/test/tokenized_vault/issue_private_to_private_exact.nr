use crate::{test::utils::{self, mint_amount}, Token};
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test(should_fail_with = "No contract instance found for address 0x0000000000000000000000000000000000000000000000000000000000000000")]
unconstrained fn issue_private_to_private_exact_without_asset() {
    let (env, vault_address, owner, recipient, _) = utils::setup_with_minter(true);

    // Issue should fail because the PublicImmutable asset was not initialized
    env.call_private(
        owner,
        Token::at(vault_address).issue_private_to_private_exact(
            owner,
            recipient,
            mint_amount,
            mint_amount,
            0,
        ),
    );
}

#[test]
unconstrained fn issue_private_to_private_exact_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Issue shares
    // At the first deposit 1 share = 1 asset
    let max_assets = deposit_amount;
    let requested_shares = deposit_amount;
    env.call_private(
        owner,
        Token::at(vault_address).issue_private_to_private_exact(
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
unconstrained fn issue_private_to_private_exact_after_yield() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to the vault contract
    let yield_amount: u128 = 1;
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Issue shares
    let max_assets: u128 = deposit_amount;
    let requested_shares = deposit_amount / 2; // The initial rate, when shares' supply is still 0, is given by the amount of assets held by the vault + 1. Since yield = 1, the rate is 1:2.
    env.call_private(
        owner,
        Token::at(vault_address).issue_private_to_private_exact(
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
    utils::check_public_balance(env, asset_address, vault_address, max_assets + yield_amount);
}

#[test]
unconstrained fn issue_private_to_private_exact_too_many_assets() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let max_deposit: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, max_deposit));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        max_deposit,
        0,
    );

    // Issue shares
    // At the first deposit 1 share = 1 asset
    let requested_shares = max_deposit - 1; // But should receive deposit_amount
    env.call_private(
        owner,
        Token::at(vault_address).issue_private_to_private_exact(
            owner,
            recipient,
            requested_shares,
            max_deposit,
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
    utils::check_public_balance(env, asset_address, vault_address, requested_shares);
    utils::check_private_balance(env, asset_address, owner, 1);
}

#[test(should_fail_with = "Assertion failed: attempt to subtract with overflow ")]
unconstrained fn issue_private_to_private_exact_request_too_many_shares() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Issue shares
    // At the first deposit 1 share = 1 asset
    let max_assets = deposit_amount;
    let requested_shares = deposit_amount + 1;
    env.call_private(
        owner,
        Token::at(vault_address).issue_private_to_private_exact(
            owner,
            recipient,
            requested_shares,
            max_assets,
            0,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn issue_private_to_private_exact_without_asset_approval() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Issue shares
    // At the first deposit 1 share = 1 asset
    let max_assets = deposit_amount;
    env.call_private(
        owner,
        Token::at(vault_address).issue_private_to_private_exact(
            owner,
            recipient,
            deposit_amount,
            max_assets,
            0,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn issue_private_to_private_exact_on_behalf_of_wrong_caller() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Issue shares
    // At the first deposit 1 share = 1 asset
    let max_assets = deposit_amount;
    env.call_private(
        recipient,
        Token::at(vault_address).issue_private_to_private_exact(
            owner,
            recipient,
            deposit_amount,
            max_assets,
            0,
        ),
    );
}

#[test]
unconstrained fn issue_private_to_private_exact_on_behalf_of_other_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    // Authorize the recipient to call issue_private_to_private_exact
    // At the first deposit 1 share = 1 asset
    let max_assets = deposit_amount;
    let requested_shares = deposit_amount;
    let issue_private_to_private_exact_call_interface = Token::at(vault_address)
        .issue_private_to_private_exact(owner, recipient, requested_shares, max_assets, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        env,
        owner,
        recipient,
        issue_private_to_private_exact_call_interface,
    );

    // Issue shares
    env.call_private(
        owner,
        Token::at(vault_address).issue_private_to_private_exact(
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
