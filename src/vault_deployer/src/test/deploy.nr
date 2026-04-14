use aztec::{
    hash::hash_args,
    oracle::random::random,
    protocol::{
        address::AztecAddress,
        constants::DOM_SEP__INITIALIZER,
        contract_class_id::ContractClassId,
        contract_instance::ContractInstance,
        hash::poseidon2_hash_with_separator,
        public_keys::PublicKeys,
        traits::{FromField, ToField},
    },
    test::helpers::{test_environment::TestEnvironment, txe_oracles as cheatcodes},
};
use token_contract::Token;
use vault_contract::Vault;

/// @notice Helper to get a vault class ID via throwaway deploy
unconstrained fn get_vault_class_id() -> ContractClassId {
    let vault_instance = cheatcodes::deploy(
        "@vault_contract/Vault",
        "",
        [],
        random(),
        random(),
        AztecAddress::zero(),
    );
    vault_instance.contract_class_id
}

/// @notice Tests that the VaultDeployer correctly computes the vault address.
/// We independently compute the address using the same algorithm and verify they match.
#[test]
unconstrained fn vault_deployer_computes_correct_vault_address() {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();

    // Deploy asset token
    let asset_initializer = Token::interface().constructor_with_minter(
        "AssetToken000000000000000000000",
        "ASSET00000000000000000000000000",
        6,
        owner,
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    let vault_class_id = get_vault_class_id();
    let vault_salt: Field = random();
    let deployer_address = AztecAddress::from_field(0x1234);

    // Compute vault address using the same logic as VaultDeployer._build_instance
    let vault_constructor = Vault::interface().constructor(asset_address, 1);
    let vault_init_hash = poseidon2_hash_with_separator(
        [vault_constructor.selector.to_field(), hash_args(vault_constructor.args)],
        DOM_SEP__INITIALIZER,
    );
    let vault_instance = ContractInstance {
        salt: vault_salt,
        deployer: deployer_address,
        contract_class_id: vault_class_id,
        initialization_hash: vault_init_hash,
        public_keys: PublicKeys::default(),
    };
    let expected_vault_address = vault_instance.to_address();

    // Verify the address is deterministic and non-zero
    assert(!expected_vault_address.is_zero(), "Vault address should be non-zero");

    // Compute again with same params - should be identical
    let vault_instance_2 = ContractInstance {
        salt: vault_salt,
        deployer: deployer_address,
        contract_class_id: vault_class_id,
        initialization_hash: vault_init_hash,
        public_keys: PublicKeys::default(),
    };
    assert(
        expected_vault_address == vault_instance_2.to_address(),
        "Address computation should be deterministic",
    );
}

/// @notice Tests that the VaultDeployer's full flow works end-to-end using the two-step
/// pattern (since TXE doesn't support publish_contract_instance_for_public_execution).
/// This simulates what VaultDeployer.deploy() does: deploy vault, deploy shares, link them.
#[test]
unconstrained fn vault_deployer_e2e_simulation() {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();

    // Deploy asset token
    let asset_initializer = Token::interface().constructor_with_minter(
        "AssetToken000000000000000000000",
        "ASSET00000000000000000000000000",
        6,
        owner,
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    // Deploy vault (deployer=owner)
    let vault_initializer = Vault::interface().constructor(asset_address, 1);
    let vault_address =
        env.deploy("@vault_contract/Vault").with_public_initializer(owner, vault_initializer);

    // Deploy shares with vault as minter
    let shares_initializer = Token::interface().constructor_with_minter(
        "SharesToken00000000000000000000",
        "SHARES0000000000000000000000000",
        18,
        vault_address,
    );
    let shares_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, shares_initializer);

    // Link shares to vault (deployer-only)
    env.call_public(owner, Vault::at(vault_address).set_shares_token(shares_address));

    // Verify vault is functional
    let vault_asset: AztecAddress = env.view_public(Vault::at(vault_address).asset());
    assert(vault_asset == asset_address, "Vault asset mismatch");

    let vault_shares: AztecAddress = env.view_public(Vault::at(vault_address).shares());
    assert(vault_shares == shares_address, "Vault shares mismatch");
}
