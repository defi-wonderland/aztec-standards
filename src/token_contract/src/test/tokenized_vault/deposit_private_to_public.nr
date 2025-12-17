use crate::{test::utils::{self, mint_amount}, Token};
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test(should_fail_with = "No contract instance found for address 0x0000000000000000000000000000000000000000000000000000000000000000")]
unconstrained fn deposit_private_to_public_without_asset() {
    let (env, vault_address, owner, recipient, _) = utils::setup_with_minter(true);

    // Deposit should fail because the PublicImmutable asset was not initialized
    env.call_private(
        owner,
        Token::at(vault_address).deposit_private_to_public(owner, recipient, mint_amount, 0),
    );
}

#[test]
unconstrained fn deposit_private_to_public_success() {
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

    // Deposit
    env.call_private(
        owner,
        Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0),
    );

    // Check recipient got shares
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    utils::check_public_balance(env, vault_address, recipient, shares);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(vault_address).total_supply());

    assert(total_supply == shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(env, asset_address, vault_address, deposit_amount);
}

#[test]
unconstrained fn deposit_private_to_public_after_yield() {
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

    // Deposit
    env.call_private(
        owner,
        Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0),
    );

    // Check recipient got shares
    let expected_shares: u128 = deposit_amount / 2; // The initial rate, when shares' supply is still 0, is given by the amount of assets held by the vault + 1. Since yield = 1, the rate is 1:2.
    utils::check_public_balance(env, vault_address, recipient, expected_shares);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(vault_address).total_supply());
    assert(total_supply == expected_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(
        env,
        asset_address,
        vault_address,
        deposit_amount + yield_amount,
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn deposit_private_to_public_without_asset_approval() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit
    env.call_private(
        owner,
        Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn deposit_private_to_public_on_behalf_of_wrong_caller() {
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

    // Deposit
    env.call_private(
        recipient,
        Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0),
    );
}

#[test]
unconstrained fn deposit_private_to_public_on_behalf_of_other_success() {
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

    // Authorize the recipient to call deposit_private_to_public
    let deposit_private_to_public_call_interface =
        Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        owner,
        recipient,
        deposit_private_to_public_call_interface,
    );

    // Deposit
    env.call_private(
        owner,
        Token::at(vault_address).deposit_private_to_public(owner, recipient, deposit_amount, 0),
    );

    // Check recipient got shares
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    utils::check_public_balance(env, vault_address, recipient, shares);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(vault_address).total_supply());
    assert(total_supply == shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(env, asset_address, vault_address, deposit_amount);
}
