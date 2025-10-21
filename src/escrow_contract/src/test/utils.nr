use crate::Escrow;
use aztec::{
    protocol_types::address::AztecAddress,
    test::helpers::{
        test_environment::TestEnvironment, txe_oracles as cheatcodes, utils::ContractDeployment,
    },
};
use nft::test::utils as nft_utils;
use token::test::utils as token_utils;

pub unconstrained fn set_escrow_with_token_and_nft(
    with_account_contracts: bool,
    escrow_secret: Field,
    ) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, recipient, minter) =
        token_utils::setup_with_minter(with_account_contracts);

    let nft_contract_address = nft_utils::deploy_nft_with_minter(&mut env, owner, minter);

    // Deploy escrow contract
    let escrow_contract_address = deploy_escrow_with_secret(&mut env, escrow_secret);

    (
        env, escrow_contract_address, token_contract_address, nft_contract_address, owner,
        recipient, minter,
    )
}

pub unconstrained fn deploy_escrow_with_secret(
    env: &mut TestEnvironment,
    escrow_secret: Field,
) -> AztecAddress {
    // Create an account with the custom secret, which generates the public keys
    // This registers the public keys with the test environment so the escrow can decrypt notes
    let _escrow_account = cheatcodes::add_account(escrow_secret);

    // Deploy the Escrow contract using escrow_secret as the salt
    let _escrow_contract =
        ContractDeployment { env: *env, path: "@escrow_contract/Escrow", secret: escrow_secret };

    _escrow_contract.without_initializer()
}
