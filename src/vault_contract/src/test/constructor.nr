use crate::Vault;
use aztec::{
    oracle::random::random,
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
    let vault_instance = cheatcodes::deploy(
        "@vault_contract/Vault",
        vault_initializer.name,
        vault_initializer.args,
        0,
        random(),
        owner,
    );
    let vault_address = vault_instance.to_address();
    env.call_public(owner, Vault::at(vault_address).constructor(asset_address, 1));
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

    let vault_init = Vault::interface().constructor(asset_address, 0);
    let vault_instance = cheatcodes::deploy(
        "@vault_contract/Vault",
        vault_init.name,
        vault_init.args,
        0,
        random(),
        owner,
    );
    let vault_address = vault_instance.to_address();
    env.call_public(owner, Vault::at(vault_address).constructor(asset_address, 0));
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

    // Deploy vault with deployer=0 (universal), call from real address
    // Constructor reads instance.deployer and rejects zero
    let vault_init = Vault::interface().constructor(asset_address, 1);
    let vault_instance = cheatcodes::deploy(
        "@vault_contract/Vault",
        vault_init.name,
        vault_init.args,
        0,
        random(),
        AztecAddress::zero(),
    );
    let vault_address = vault_instance.to_address();
    env.call_public(owner, Vault::at(vault_address).constructor(asset_address, 1));
}
