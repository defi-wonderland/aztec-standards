use crate::Token;
use aztec::{prelude::AztecAddress, test::helpers::{cheatcodes, test_environment::TestEnvironment}};
use aztec::test::helpers::authwit as authwit_cheatcodes;

pub unconstrained fn mint_and_deposit_public_to_public(
    env: &mut TestEnvironment,
    minter: AztecAddress,
    asset_address: AztecAddress,
    vault_address: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
) {
    env.impersonate(minter);
    Token::at(asset_address).mint_to_public(minter, amount).call(&mut env.public());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface =
        Token::at(asset_address).transfer_public_to_public(minter, vault_address, amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        minter,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit
    env.impersonate(minter);
    Token::at(vault_address).deposit_public_to_public(minter, recipient, amount, 0).call(
        &mut env.public(),
    );
    env.advance_block_by(1);
}

pub unconstrained fn mint_and_deposit_public_to_private(
    env: &mut TestEnvironment,
    minter: AztecAddress,
    asset_address: AztecAddress,
    vault_address: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
) {
    env.impersonate(minter);
    Token::at(asset_address).mint_to_public(minter, amount).call(&mut env.public());
    env.advance_block_by(1);

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface =
        Token::at(asset_address).transfer_public_to_public(minter, vault_address, amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        minter,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit
    env.impersonate(minter);
    Token::at(vault_address).deposit_public_to_private(minter, recipient, amount, amount, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);
}
