use crate::{test::{tokenized_vault::tokenized_vault_utils, utils::{self, mint_amount}}, Token};
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test(should_fail_with = "Artifact not found when calling private function. Contract address: 0x0000000000000000000000000000000000000000000000000000000000000000.")]
unconstrained fn redeem_public_to_private_exact_without_asset() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (_, asset_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);

    let (env, vault_address, _, _, minter) = utils::setup_with_minter(false);

    // Withdrawal should fail because the PublicImmutable asset was not initialized
    env.impersonate(owner);
    Token::at(vault_address).redeem_public_to_private_exact(owner, recipient, 0, 0, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);
}

// TODO(#15666 & #15118): this test fails because the ivsk is currently needed for emitting a note, but the vault contract doesn't have one.
// #[test]
#[test(should_fail_with = "No public key registered for address")]
unconstrained fn redeem_public_to_private_exact_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

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

    env.impersonate(deposit_recipient);
    let shares_to_burn: u128 = deposit_amount;
    let min_assets: u128 = deposit_amount;
    Token::at(vault_address)
        .redeem_public_to_private_exact(deposit_recipient, recipient, shares_to_burn, min_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // All shares are burnt
    utils::check_public_balance(vault_address, deposit_recipient, 0);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances
    utils::check_public_balance(asset_address, recipient, deposit_amount);
    utils::check_public_balance(asset_address, vault_address, 0);
}

// TODO(#15666 & #15118): this test fails because the ivsk is currently needed for emitting a note, but the vault contract doesn't have one.
// #[test]
#[test(should_fail_with = "No public key registered for address")]
unconstrained fn redeem_public_to_private_exact_after_yield() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

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
    env.impersonate(owner);
    Token::at(asset_address).mint_to_public(vault_address, yield_amount).call(&mut env.public());
    env.advance_block_by(1);

    // Withdraw
    let shares_to_burn: u128 = deposit_amount;
    let min_assets: u128 = deposit_amount + 1;
    env.impersonate(deposit_recipient);
    Token::at(vault_address)
        .redeem_public_to_private_exact(deposit_recipient, recipient, shares_to_burn, min_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // All shares are burnt
    utils::check_public_balance(vault_address, deposit_recipient, 0);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances. The vault should still have 1 token due to rounding.
    utils::check_public_balance(asset_address, vault_address, 1);
    utils::check_public_balance(asset_address, recipient, deposit_amount + 1);
}

// TODO(#15666 & #15118): this test fails because the ivsk is currently needed for emitting a note, but the vault contract doesn't have one.
// #[test]
#[test(should_fail_with = "No public key registered for address")]
unconstrained fn redeem_public_to_private_exact_request_fewer_assets() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

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

    env.impersonate(deposit_recipient);
    let shares_to_burn: u128 = deposit_amount;
    let min_assets: u128 = deposit_amount - 1;
    Token::at(vault_address)
        .redeem_public_to_private_exact(deposit_recipient, recipient, shares_to_burn, min_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // The deposit_recipient receives change, since he sent 1 share too many
    utils::check_private_balance(vault_address, deposit_recipient, 1);
    utils::check_public_balance(vault_address, deposit_recipient, 0);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == 1, "Incorrect shares total supply");

    // Check asset balances
    utils::check_public_balance(asset_address, recipient, min_assets);
    utils::check_public_balance(asset_address, vault_address, 1);
}

// TODO: this test should fail because the ivsk is currently needed for emitting a note, but the vault contract doesn't have one.
// However, tests written in noir execute enqueued public call immediately instead of at the end of private execution.
// #[test(should_fail_with = "No public key registered for address")]
#[test(should_fail_with = "Assertion failed: attempt to subtract with overflow")]
unconstrained fn redeem_public_to_private_exact_request_too_many_assets() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(false);

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

    env.impersonate(deposit_recipient);
    let shares_to_burn: u128 = deposit_amount - 1;
    let min_assets: u128 = deposit_amount;
    Token::at(vault_address)
        .redeem_public_to_private_exact(deposit_recipient, recipient, shares_to_burn, min_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn redeem_public_to_private_exact_without_approval() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

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
    env.impersonate(recipient);
    let shares_to_burn: u128 = deposit_amount;
    let min_assets: u128 = deposit_amount;
    Token::at(vault_address)
        .redeem_public_to_private_exact(deposit_recipient, recipient, shares_to_burn, min_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn redeem_public_to_private_exact_on_behalf_of_wrong_caller() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

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
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        deposit_recipient,
        owner,
        redeem_public_to_private_exact_call_interface,
    );

    // Withdraw
    env.impersonate(recipient);
    Token::at(vault_address)
        .redeem_public_to_private_exact(deposit_recipient, recipient, shares_to_burn, min_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);
}

// TODO(#15666 & #15118): this test fails because the ivsk is currently needed for emitting a note, but the vault contract doesn't have one.
// #[test]
#[test(should_fail_with = "No public key registered for address")]
unconstrained fn redeem_public_to_private_exact_on_behalf_of_other_success() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

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
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        deposit_recipient,
        recipient,
        redeem_public_to_private_exact_call_interface,
    );

    // Withdraw
    env.impersonate(recipient);
    Token::at(vault_address)
        .redeem_public_to_private_exact(deposit_recipient, recipient, shares_to_burn, min_assets, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // All shares are burnt
    utils::check_public_balance(vault_address, deposit_recipient, 0);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == 0, "Incorrect shares total supply");

    // Check asset balances
    utils::check_private_balance(asset_address, recipient, min_assets);
    utils::check_public_balance(asset_address, vault_address, 0);
}
