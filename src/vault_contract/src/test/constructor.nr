use crate::Vault;
use aztec::{
    protocol::address::AztecAddress,
    test::helpers::{test_environment::TestEnvironment, txe_oracles as cheatcodes},
};
use token_contract::Token;

#[test]
unconstrained fn constructor_success() {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();

    let asset_initializer = Token::interface().constructor_with_minter(
        "AssetToken000000000000000000000",
        "ASSET00000000000000000000000000",
        6,
        owner,
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    let vault_initializer = Vault::interface().constructor(asset_address, 1);
    let _vault_address =
        env.deploy("@vault_contract/Vault").with_public_initializer(owner, vault_initializer);
}

#[test(should_fail_with = "vault_offset must be greater than 0")]
unconstrained fn constructor_fail_zero_offset() {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();

    let asset_initializer = Token::interface().constructor_with_minter(
        "AssetToken000000000000000000000",
        "ASSET00000000000000000000000000",
        6,
        owner,
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    let vault_initializer = Vault::interface().constructor(asset_address, 0);
    let _vault_address =
        env.deploy("@vault_contract/Vault").with_public_initializer(owner, vault_initializer);
}

#[test(should_fail_with = "universal deploy not supported")]
unconstrained fn constructor_fail_universal_deploy() {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();

    let asset_initializer = Token::interface().constructor_with_minter(
        "AssetToken000000000000000000000",
        "ASSET00000000000000000000000000",
        6,
        owner,
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    // Deploy vault instance with deployer=0 (universal deploy), then call initializer
    let vault_init = Vault::interface().constructor(asset_address, 1);
    let vault_instance = cheatcodes::deploy(
        "@vault_contract/Vault",
        vault_init.name,
        vault_init.args,
        0,
        0,
        AztecAddress::zero(),
    );
    let vault_address = vault_instance.to_address();

    // Calling the initializer should fail because msg_sender == deployer == 0
    env.call_public(AztecAddress::zero(), Vault::at(vault_address).constructor(asset_address, 1));
}
