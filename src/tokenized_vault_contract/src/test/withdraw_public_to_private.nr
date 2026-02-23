use crate::test::utils::{self, mint_amount};
use crate::TokenizedVault;
use aztec::test::helpers::authwit as authwit_cheatcodes;
use aztec::test::helpers::test_environment::TestEnvironment;
use generic_proxy::GenericProxy;
use token_contract::Token;

#[test(should_fail_with = "Trying to read from uninitialized PublicImmutable")]
unconstrained fn withdraw_public_to_private_without_asset() {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();
    let recipient = env.create_light_account();
    let vault_address =
        env.deploy("@tokenized_vault_contract/TokenizedVault").without_initializer();

    // Withdrawal should fail because the PublicImmutable asset was not initialized
    env.call_private(
        owner,
        TokenizedVault::at(vault_address).withdraw_public_to_private(
            owner,
            recipient,
            mint_amount,
            0,
        ),
    );
}

#[test]
unconstrained fn withdraw_public_to_private_success() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, shares_address) =
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

    // Authorize the vault to burn shares from the depositor on the shares token (public burn in settlement)
    utils::authorize_burn_public(
        env,
        shares_address,
        vault_address,
        deposit_recipient,
        deposit_amount,
        0,
    );

    env.call_private(
        deposit_recipient,
        TokenizedVault::at(vault_address).withdraw_public_to_private(
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
    utils::check_private_balance(env, asset_address, recipient, deposit_amount);
    utils::check_public_balance(env, asset_address, vault_address, 0);
}

#[test]
unconstrained fn withdraw_public_to_private_after_yield() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, shares_address) =
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

    // Authorize the vault to burn shares from the depositor on the shares token (public burn in settlement)
    utils::authorize_burn_public(
        env,
        shares_address,
        vault_address,
        deposit_recipient,
        deposit_amount,
        0,
    );

    // Withdraw
    env.call_private(
        deposit_recipient,
        TokenizedVault::at(vault_address).withdraw_public_to_private(
            deposit_recipient,
            recipient,
            deposit_amount + 1,
            0,
        ),
    );

    // All shares are burnt
    utils::check_public_balance(env, shares_address, deposit_recipient, 0);
    utils::check_public_balance(env, shares_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances. The vault should still have 1 token due to rounding.
    utils::check_public_balance(env, asset_address, vault_address, 1);
    utils::check_private_balance(env, asset_address, recipient, deposit_amount + 1);
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn withdraw_public_to_private_without_approval() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(true);

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

    // Withdraw
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
    let call_interface = TokenizedVault::at(vault_address).withdraw_public_to_private(
        deposit_recipient,
        recipient,
        deposit_amount,
        0,
    );
    // No authwit added from deposit_recipient to proxy
    env.call_private(
        deposit_recipient,
        GenericProxy::at(proxy).forward_private_4(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn withdraw_public_to_private_on_behalf_of_wrong_caller() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(true);

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

    // Authorize someone to call withdraw_public_to_private (but authorize owner, not proxy)
    let withdraw_public_to_private_call_interface = TokenizedVault::at(vault_address)
        .withdraw_public_to_private(deposit_recipient, recipient, deposit_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        deposit_recipient,
        owner,
        withdraw_public_to_private_call_interface,
    );

    // Withdraw
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
    let call_interface = TokenizedVault::at(vault_address).withdraw_public_to_private(
        deposit_recipient,
        recipient,
        deposit_amount,
        0,
    );
    // No authwit added from deposit_recipient to proxy
    env.call_private(
        deposit_recipient,
        GenericProxy::at(proxy).forward_private_4(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );
}

#[test]
unconstrained fn withdraw_public_to_private_on_behalf_of_other_success() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(true);
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();

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

    // Authwit 1: Authorize the proxy to call withdraw_public_to_private on the vault on behalf of deposit_recipient
    let call_interface = TokenizedVault::at(vault_address).withdraw_public_to_private(
        deposit_recipient,
        recipient,
        deposit_amount,
        0,
    );
    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        deposit_recipient,
        proxy,
        call_interface,
    );

    // Authwit 2: Authorize the vault to burn shares from deposit_recipient on the shares token (public burn in settlement)
    utils::authorize_burn_public(
        env,
        shares_address,
        vault_address,
        deposit_recipient,
        deposit_amount,
        0,
    );

    // Withdraw
    env.call_private(
        deposit_recipient,
        GenericProxy::at(proxy).forward_private_4(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );

    // All shares are burnt
    utils::check_public_balance(env, shares_address, deposit_recipient, 0);
    utils::check_public_balance(env, shares_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances
    utils::check_private_balance(env, asset_address, recipient, deposit_amount);
    utils::check_public_balance(env, asset_address, vault_address, 0);
}
