use crate::Escrow;
use aztec::{prelude::AztecAddress, test::helpers::{cheatcodes, test_environment::TestEnvironment}};
use nft::test::utils as nft_utils;
use token::test::utils as token_utils;

pub unconstrained fn set_escrow_with_token_and_nft(
    with_account_contracts: bool,
    escrow_secret: Field,
    ) -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, recipient, minter) =
        token_utils::setup_with_minter(with_account_contracts);

    let nft_contract_address = nft_utils::deploy_nft_with_minter(env, owner, minter);

    // Deploy escrow contract
    let escrow_contract_address = deploy_escrow_with_secret(env, escrow_secret);

    (
        env, escrow_contract_address, token_contract_address, nft_contract_address, owner,
        recipient, minter,
    )
}

pub unconstrained fn deploy_escrow_with_secret(
    env: &mut TestEnvironment,
    escrow_secret: Field,
) -> AztecAddress {
    let escrow_contract_account = cheatcodes::add_account(escrow_secret);

    let escrow_contract = env
        .deploy_with_public_keys("./@escrow_contract", "Escrow", escrow_secret)
        .without_initializer();
    env.advance_block_by(1);

    escrow_contract.to_address()
}
