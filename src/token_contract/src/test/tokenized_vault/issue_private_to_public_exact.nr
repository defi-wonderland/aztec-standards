use crate::{test::utils::{self, mint_amount}, Token};
use authwit::cheatcodes as authwit_cheatcodes;

#[test]
unconstrained fn issue_public_to_private_exact_too_many_assets() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, asset_address) = utils::setup_with_asset(true);

    // Mint some asset tokens to owner
    let max_deposit: u128 = mint_amount;
    env.impersonate(owner);
    Token::at(asset_address).mint_to_private(owner, owner, max_deposit).call(&mut env.private());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let transfer_private_to_public_call_interface =
        Token::at(asset_address).transfer_private_to_public(owner, vault_address, max_deposit, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        vault_address,
        transfer_private_to_public_call_interface,
    );

    // Deposit
    env.impersonate(owner);
    // At the first deposit 1 share = 1 asset
    let requested_shares = 9_999; // But should receive 10_000
    Token::at(vault_address)
        .issue_private_to_public_exact(owner, recipient, requested_shares, max_deposit, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got shares
    utils::check_private_balance(vault_address, recipient, requested_shares);
    utils::check_public_balance(vault_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    assert(total_supply == requested_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(asset_address, vault_address, requested_shares);
    utils::check_private_balance(asset_address, owner, 1);
}
