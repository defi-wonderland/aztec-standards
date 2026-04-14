pub mod test;

use aztec::macros::aztec;

/// @title VaultDeployer
/// @notice Atomically deploys a Vault + shares token pair in a single transaction.
/// @dev Computes both contract addresses on-chain from the provided class IDs, salts, and
///      constructor args. Both instances use this contract as their deployer (non-universal
///      deploy) so that:
///      1. publish_contract_instance_for_public_execution passes the deployer check
///      2. vault.set_shares_token passes the deployer == msg_sender check
///
///      The SDK must register the same instance preimages with the PXE before calling deploy()
///      so the get_contract_instance oracle can resolve them.
#[aztec]
pub contract VaultDeployer {
    use aztec::{
        hash::hash_args,
        macros::functions::{external, initializer},
        protocol::{
            address::AztecAddress, constants::DOM_SEP__INITIALIZER,
            contract_class_id::ContractClassId, contract_instance::ContractInstance,
            hash::poseidon2_hash_with_separator, public_keys::PublicKeys, traits::ToField,
        },
        publish_contract_instance::publish_contract_instance_for_public_execution,
    };
    use token_contract::Token;
    use vault_contract::Vault;

    #[external("public")]
    #[initializer]
    fn constructor() {}

    /// @notice Deploys a vault and its shares token atomically
    /// @param asset The underlying asset token address
    /// @param vault_offset The offset used to prevent inflation attacks (typically 1)
    /// @param vault_class_id The contract class ID of the vault contract
    /// @param vault_salt The salt for vault deployment
    /// @param shares_name The name of the shares token
    /// @param shares_symbol The symbol of the shares token
    /// @param shares_decimals The number of decimals for the shares token
    /// @param shares_class_id The contract class ID of the shares token contract
    /// @param shares_salt The salt for shares token deployment
    #[external("private")]
    fn deploy(
        asset: AztecAddress,
        vault_offset: u128,
        vault_class_id: ContractClassId,
        vault_salt: Field,
        shares_name: str<31>,
        shares_symbol: str<31>,
        shares_decimals: u8,
        shares_class_id: ContractClassId,
        shares_salt: Field,
    ) {
        let vault_constructor = Vault::interface().constructor(asset, vault_offset);
        let vault = _build_instance(
            vault_constructor.selector.to_field(),
            hash_args(vault_constructor.args),
            vault_class_id,
            vault_salt,
            self.address,
        )
            .to_address();

        let shares_constructor = Token::interface().constructor_with_minter(
            shares_name,
            shares_symbol,
            shares_decimals,
            vault,
        );
        let shares = _build_instance(
            shares_constructor.selector.to_field(),
            hash_args(shares_constructor.args),
            shares_class_id,
            shares_salt,
            self.address,
        )
            .to_address();

        publish_contract_instance_for_public_execution(self.context, vault);
        publish_contract_instance_for_public_execution(self.context, shares);

        self.enqueue(Vault::at(vault).constructor(asset, vault_offset));
        self.enqueue(Token::at(shares).constructor_with_minter(
            shares_name,
            shares_symbol,
            shares_decimals,
            vault,
        ));
        self.enqueue(Vault::at(vault).set_shares_token(shares));
    }

    /// @notice Deploys a vault and its shares token atomically, with an initial deposit
    /// @dev The depositor must have authorized the vault to transfer initial_deposit of
    ///      the asset token via authwit before this tx is submitted.
    #[external("private")]
    fn deploy_with_initial_deposit(
        asset: AztecAddress,
        vault_offset: u128,
        vault_class_id: ContractClassId,
        vault_salt: Field,
        shares_name: str<31>,
        shares_symbol: str<31>,
        shares_decimals: u8,
        shares_class_id: ContractClassId,
        shares_salt: Field,
        initial_deposit: u128,
        depositor: AztecAddress,
        nonce: Field,
    ) {
        let vault_constructor = Vault::interface().constructor(asset, vault_offset);
        let vault = _build_instance(
            vault_constructor.selector.to_field(),
            hash_args(vault_constructor.args),
            vault_class_id,
            vault_salt,
            self.address,
        )
            .to_address();

        let shares_constructor = Token::interface().constructor_with_minter(
            shares_name,
            shares_symbol,
            shares_decimals,
            vault,
        );
        let shares = _build_instance(
            shares_constructor.selector.to_field(),
            hash_args(shares_constructor.args),
            shares_class_id,
            shares_salt,
            self.address,
        )
            .to_address();

        publish_contract_instance_for_public_execution(self.context, vault);
        publish_contract_instance_for_public_execution(self.context, shares);

        self.enqueue(Vault::at(vault).constructor(asset, vault_offset));
        self.enqueue(Token::at(shares).constructor_with_minter(
            shares_name,
            shares_symbol,
            shares_decimals,
            vault,
        ));
        self.enqueue(Vault::at(vault).set_shares_token_with_initial_deposit(
            shares,
            initial_deposit,
            depositor,
            nonce,
        ));
    }

    #[contract_library_method]
    fn _build_instance(
        selector: Field,
        args_hash: Field,
        class_id: ContractClassId,
        salt: Field,
        deployer: AztecAddress,
    ) -> ContractInstance {
        let initialization_hash =
            poseidon2_hash_with_separator([selector, args_hash], DOM_SEP__INITIALIZER);

        ContractInstance {
            salt,
            deployer,
            contract_class_id: class_id,
            initialization_hash,
            public_keys: PublicKeys::default(),
        }
    }
}
