use crate::Token;
use aztec::{protocol::address::AztecAddress, test::helpers::test_environment::TestEnvironment};
use aztec::test::helpers::authwit as authwit_cheatcodes;

pub unconstrained fn mint_and_deposit_public_to_public(
    env: TestEnvironment,
    minter: AztecAddress,
    asset_address: AztecAddress,
    vault_address: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
) {
    env.call_public(minter, Token::at(asset_address).mint_to_public(minter, amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface =
        Token::at(asset_address).transfer_public_to_public(minter, vault_address, amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call(
        env,
        minter,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit
    env.call_public(
        minter,
        Token::at(vault_address).deposit_public_to_public(minter, recipient, amount, 0),
    );
}

pub unconstrained fn mint_and_deposit_public_to_private(
    env: TestEnvironment,
    minter: AztecAddress,
    asset_address: AztecAddress,
    vault_address: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
) {
    env.call_public(minter, Token::at(asset_address).mint_to_public(minter, amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    let public_transfer_public_to_public_call_interface =
        Token::at(asset_address).transfer_public_to_public(minter, vault_address, amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call(
        env,
        minter,
        vault_address,
        public_transfer_public_to_public_call_interface,
    );

    // Deposit
    env.call_private(
        minter,
        Token::at(vault_address).deposit_public_to_private(minter, recipient, amount, amount, 0),
    );
}
