use crate::test::utils::{self, mint_amount};
use crate::Vault;
use aztec::test::helpers::authwit as authwit_cheatcodes;
use token_contract::Token;

#[test(should_fail_with = "Trying to read from uninitialized PublicImmutable")]
unconstrained fn deposit_public_to_public_without_shares() {
    let (env, vault_address, owner, recipient, _asset_address) =
        utils::setup_vault_without_shares();

    env.call_public(
        owner,
        Vault::at(vault_address).deposit_public_to_public(owner, recipient, mint_amount, 0),
    );
}

#[test]
unconstrained fn deposit_public_to_public_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(false);

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
    );

    // Deposit
    env.call_public(
        owner,
        Vault::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0),
    );

    // Check recipient got shares
    // At the first deposit 1 share = 1 asset
    utils::check_public_balance(env, shares_address, recipient, deposit_amount);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == deposit_amount, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(env, asset_address, vault_address, deposit_amount);
}

#[test]
unconstrained fn deposit_public_to_public_after_yield() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(false);

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
    );

    // Deposit
    env.call_public(
        owner,
        Vault::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0),
    );

    // Check recipient got shares
    let expected_shares: u128 = deposit_amount / 2; // The initial rate, when shares' supply is still 0, is given by the amount of assets held by the vault + 1. Since yield = 1, the rate is 1:2.
    utils::check_public_balance(env, shares_address, recipient, expected_shares);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == expected_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(
        env,
        asset_address,
        vault_address,
        deposit_amount + yield_amount,
    );
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn deposit_public_to_public_without_asset_approval() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address, _shares_address) =
        utils::setup_with_vault(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, deposit_amount));

    // Deposit
    env.call_public(
        owner,
        Vault::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0),
    );
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn deposit_public_to_public_on_behalf_of_wrong_caller() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address, _shares_address) =
        utils::setup_with_vault(false);

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
    );

    // Deposit
    env.call_public(
        recipient,
        Vault::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0),
    );
}

#[test]
unconstrained fn deposit_public_to_public_on_behalf_of_other_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, deposit_amount));

    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_public_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Authorize the recipient to call deposit_public_to_public
    let deposit_public_to_public_call_interface =
        Vault::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call(
        env,
        owner,
        recipient,
        deposit_public_to_public_call_interface,
    );

    // Deposit
    env.call_public(
        recipient,
        Vault::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0),
    );

    // Check recipient got shares
    // At the first deposit 1 share = 1 asset
    utils::check_public_balance(env, shares_address, recipient, deposit_amount);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == deposit_amount, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(env, asset_address, vault_address, deposit_amount);
}
