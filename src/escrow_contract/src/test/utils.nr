use aztec::{
    oracle::random::random,
    protocol::{address::AztecAddress, traits::ToField},
    test::helpers::{
        test_environment::TestEnvironment, txe_oracles as cheatcodes, utils::ContractDeployment,
    },
};
use nft::test::utils as nft_utils;
use token::test::utils as token_utils;

pub unconstrained fn set_escrow_with_token_and_nft(
    with_account_contracts: bool,
    escrow_secret: Field,
    ) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, token_contract_address, owner, recipient, minter) =
        token_utils::setup_with_minter(with_account_contracts);

    let nft_contract_address = nft_utils::deploy_nft_with_minter(&mut env, owner, minter);

    // Create a light account to act as the authorized logic contract caller
    let logic_contract = env.create_light_account();

    // Deploy escrow contract with the logic contract's address encoded as the salt
    let escrow_contract_address =
        deploy_escrow_with_secret(&mut env, escrow_secret, logic_contract);

    (
        env, escrow_contract_address, token_contract_address, nft_contract_address, owner,
        recipient, minter, logic_contract,
    )
}

pub unconstrained fn deploy_escrow_with_secret(
    env: &mut TestEnvironment,
    escrow_secret: Field,
    logic_contract: AztecAddress,
) -> AztecAddress {
    let _escrow_account = cheatcodes::add_account(escrow_secret);

    let _escrow_contract = ContractDeployment {
        env: *env,
        path: "@escrow_contract/Escrow",
        secret: escrow_secret,
        salt: logic_contract.to_field(),
    };

    _escrow_contract.without_initializer()
}

pub unconstrained fn get_escrow_class_id() -> Field {
    let escrow_instance = cheatcodes::deploy("@escrow_contract/Escrow", "", [], random());
    escrow_instance.contract_class_id.to_field()
}
