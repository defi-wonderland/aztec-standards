use crate::test::utils::{self, mint_amount};
use crate::Vault;
use aztec::test::helpers::authwit as authwit_cheatcodes;
use token_contract::Token;

#[test(should_fail_with = "Trying to read from uninitialized PublicImmutable")]
unconstrained fn withdraw_public_to_public_without_shares() {
    let (env, vault_address, owner, recipient, _asset_address) =
        utils::setup_vault_without_shares();

    env.call_public(
        owner,
        Vault::at(vault_address).withdraw_public_to_public(owner, recipient, mint_amount, 0),
    );
}

#[test]
unconstrained fn withdraw_public_to_public_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        shares_address,
        deposit_recipient,
        deposit_amount,
    );

    utils::withdraw_public_to_public(
        env,
        vault_address,
        shares_address,
        deposit_recipient,
        recipient,
        deposit_amount,
        deposit_amount,
    );

    // All shares are burnt
    utils::check_public_balance(env, shares_address, deposit_recipient, 0);
    utils::check_public_balance(env, shares_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances
    utils::check_public_balance(env, asset_address, vault_address, 0);
    utils::check_public_balance(env, asset_address, recipient, deposit_amount);
}

#[test]
unconstrained fn withdraw_public_to_public_after_yield() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        shares_address,
        deposit_recipient,
        deposit_amount,
    );

    // Mint some asset tokens to the vault contract
    let yield_amount: u128 = 2; // Using 2 instead of 1 avoids rounding issues from anti-inflation logic: 1 goes to the user, 1 stays in the vault.
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    utils::withdraw_public_to_public(
        env,
        vault_address,
        shares_address,
        deposit_recipient,
        recipient,
        deposit_amount + 1,
        deposit_amount,
    );

    // All shares are burnt
    utils::check_public_balance(env, shares_address, deposit_recipient, 0);
    utils::check_public_balance(env, shares_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances. The vault should still have 1 token due to rounding.
    utils::check_public_balance(env, asset_address, vault_address, 1);
    utils::check_public_balance(env, asset_address, recipient, deposit_amount + 1);
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn withdraw_public_to_public_without_approval() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        shares_address,
        deposit_recipient,
        deposit_amount,
    );

    // Withdraw (recipient calls, but has no approval from deposit_recipient on the vault)
    env.call_public(
        recipient,
        Vault::at(vault_address).withdraw_public_to_public(
            deposit_recipient,
            recipient,
            deposit_amount,
            0,
        ),
    );
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn withdraw_public_to_public_on_behalf_of_wrong_caller() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        shares_address,
        deposit_recipient,
        deposit_amount,
    );

    // Authorize someone to call withdraw_public_to_public on the vault (but authorizes owner, not recipient)
    let public_withdraw_public_to_public_call_interface = Vault::at(vault_address)
        .withdraw_public_to_public(deposit_recipient, recipient, deposit_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call(
        env,
        deposit_recipient,
        owner,
        public_withdraw_public_to_public_call_interface,
    );

    // Withdraw (recipient calls, but authwit was for owner)
    env.call_public(
        recipient,
        Vault::at(vault_address).withdraw_public_to_public(
            deposit_recipient,
            recipient,
            deposit_amount,
            0,
        ),
    );
}

#[test]
unconstrained fn withdraw_public_to_public_on_behalf_of_other_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        shares_address,
        deposit_recipient,
        deposit_amount,
    );

    // Authwit 1: Authorize recipient to call withdraw_public_to_public on the vault on behalf of deposit_recipient
    let public_withdraw_public_to_public_call_interface = Vault::at(vault_address)
        .withdraw_public_to_public(deposit_recipient, recipient, deposit_amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call(
        env,
        deposit_recipient,
        recipient,
        public_withdraw_public_to_public_call_interface,
    );

    // Authwit 2: Authorize the vault to burn shares from deposit_recipient on the shares token
    utils::authorize_burn_public(
        env,
        shares_address,
        vault_address,
        deposit_recipient,
        deposit_amount,
    );

    // Withdraw
    env.call_public(
        recipient,
        Vault::at(vault_address).withdraw_public_to_public(
            deposit_recipient,
            recipient,
            deposit_amount,
            0,
        ),
    );

    // All shares are burnt
    utils::check_public_balance(env, shares_address, deposit_recipient, 0);
    utils::check_public_balance(env, shares_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances
    utils::check_public_balance(env, asset_address, vault_address, 0);
    utils::check_public_balance(env, asset_address, recipient, deposit_amount);
}
