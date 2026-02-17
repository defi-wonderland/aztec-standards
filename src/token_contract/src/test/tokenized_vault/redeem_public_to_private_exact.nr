use crate::{test::{tokenized_vault::tokenized_vault_utils, utils::{self, mint_amount}}, Token};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

#[test(should_fail_with = "Trying to read from uninitialized PublicImmutable")]
unconstrained fn redeem_public_to_private_exact_without_asset() {
    let (mut env, vault_address, owner, recipient, _) = utils::setup_with_minter(false);

    // Withdrawal should fail because the PublicImmutable asset was not initialized
    env.call_private(
        owner,
        Token::at(vault_address).redeem_public_to_private_exact(owner, recipient, 0, 0, 0),
    );
}

#[test]
unconstrained fn redeem_public_to_private_exact_success() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        deposit_recipient,
        deposit_amount,
    );

    let shares_to_burn: u128 = deposit_amount;
    let min_assets: u128 = deposit_amount;
    env.call_private(
        deposit_recipient,
        Token::at(vault_address).redeem_public_to_private_exact(
            deposit_recipient,
            recipient,
            shares_to_burn,
            min_assets,
            0,
        ),
    );

    // All shares are burnt
    utils::check_public_balance(env, vault_address, deposit_recipient, 0);
    utils::check_public_balance(env, vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(vault_address).total_supply());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances
    utils::check_private_balance(env, asset_address, recipient, deposit_amount);
    utils::check_public_balance(env, asset_address, vault_address, 0);
}

#[test]
unconstrained fn redeem_public_to_private_exact_after_yield() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        deposit_recipient,
        deposit_amount,
    );

    // Mint some asset tokens to the vault contract
    let yield_amount: u128 = 2; // Using 2 instead of 1 avoids rounding issues from anti-inflation logic: 1 goes to the user, 1 stays in the vault.
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // Withdraw
    let shares_to_burn: u128 = deposit_amount;
    let min_assets: u128 = deposit_amount + 1;
    env.call_private(
        deposit_recipient,
        Token::at(vault_address).redeem_public_to_private_exact(
            deposit_recipient,
            recipient,
            shares_to_burn,
            min_assets,
            0,
        ),
    );

    // All shares are burnt
    utils::check_public_balance(env, vault_address, deposit_recipient, 0);
    utils::check_public_balance(env, vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(vault_address).total_supply());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances. The vault should still have 1 token due to rounding.
    utils::check_public_balance(env, asset_address, vault_address, 1);
    utils::check_private_balance(env, asset_address, recipient, deposit_amount + 1);
}

#[test]
unconstrained fn redeem_public_to_private_exact_request_fewer_assets() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        deposit_recipient,
        deposit_amount,
    );

    let shares_to_burn: u128 = deposit_amount;
    let min_assets: u128 = deposit_amount - 1;
    env.call_private(
        deposit_recipient,
        Token::at(vault_address).redeem_public_to_private_exact(
            deposit_recipient,
            recipient,
            shares_to_burn,
            min_assets,
            0,
        ),
    );

    // The deposit_recipient receives change, since he sent 1 share too many
    utils::check_private_balance(env, vault_address, deposit_recipient, 0);
    utils::check_public_balance(env, vault_address, deposit_recipient, 0);
    utils::check_public_balance(env, vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(vault_address).total_supply());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances
    utils::check_private_balance(env, asset_address, recipient, deposit_amount);
    utils::check_public_balance(env, asset_address, recipient, 0);
    utils::check_public_balance(env, asset_address, vault_address, 0);
}

#[test(should_fail_with = "Assertion failed: attempt to subtract with overflow")]
unconstrained fn redeem_public_to_private_exact_request_too_many_assets() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        deposit_recipient,
        deposit_amount,
    );

    let shares_to_burn: u128 = deposit_amount - 1;
    let min_assets: u128 = deposit_amount;
    env.call_private(
        deposit_recipient,
        Token::at(vault_address).redeem_public_to_private_exact(
            deposit_recipient,
            recipient,
            shares_to_burn,
            min_assets,
            0,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn redeem_public_to_private_exact_without_approval() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        deposit_recipient,
        deposit_amount,
    );

    // Withdraw
    let shares_to_burn: u128 = deposit_amount;
    let min_assets: u128 = deposit_amount;
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
    let call_interface = Token::at(vault_address).redeem_public_to_private_exact(
        deposit_recipient,
        recipient,
        shares_to_burn,
        min_assets,
        0,
    );
    // No authwit added from deposit_recipient to proxy
    env.call_private(
        deposit_recipient,
        GenericProxy::at(proxy).forward_private_5(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn redeem_public_to_private_exact_on_behalf_of_wrong_caller() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        deposit_recipient,
        deposit_amount,
    );

    // Authorize someone to call redeem_public_to_private_exact
    let shares_to_burn: u128 = deposit_amount;
    let min_assets: u128 = deposit_amount;
    let redeem_public_to_private_exact_call_interface = Token::at(vault_address)
        .redeem_public_to_private_exact(deposit_recipient, recipient, shares_to_burn, min_assets, 0)
        ;
    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        deposit_recipient,
        owner,
        redeem_public_to_private_exact_call_interface,
    );

    // Withdraw
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
    let call_interface = Token::at(vault_address).redeem_public_to_private_exact(
        deposit_recipient,
        recipient,
        shares_to_burn,
        min_assets,
        0,
    );
    // No authwit added from deposit_recipient to proxy
    env.call_private(
        deposit_recipient,
        GenericProxy::at(proxy).forward_private_5(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );
}

#[test]
unconstrained fn redeem_public_to_private_exact_on_behalf_of_other_success() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    let deposit_recipient = owner;
    tokenized_vault_utils::mint_and_deposit_public_to_public(
        env,
        owner,
        asset_address,
        vault_address,
        deposit_recipient,
        deposit_amount,
    );

    // Authorize the proxy to call redeem_public_to_private_exact on behalf of deposit_recipient
    let shares_to_burn: u128 = deposit_amount;
    let min_assets: u128 = deposit_amount;
    let call_interface = Token::at(vault_address).redeem_public_to_private_exact(
        deposit_recipient,
        recipient,
        shares_to_burn,
        min_assets,
        0,
    );
    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        deposit_recipient,
        proxy,
        call_interface,
    );

    // Withdraw
    env.call_private(
        deposit_recipient,
        GenericProxy::at(proxy).forward_private_5(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );

    // All shares are burnt
    utils::check_public_balance(env, vault_address, deposit_recipient, 0);
    utils::check_public_balance(env, vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(vault_address).total_supply());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances
    utils::check_private_balance(env, asset_address, recipient, min_assets);
    utils::check_public_balance(env, asset_address, vault_address, 0);
}
