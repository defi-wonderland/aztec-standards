use aztec::macros::aztec;

/// @title VaultDeployer
/// @notice Atomically deploys a Vault + shares token pair when this contract instance is created.
/// @dev Each pool deploys a new VaultDeployer instance whose initializer runs deploy_vault or
///      deploy_vault_with_initial_deposit. The vault and shares addresses depend on this instance's
///      address as deployer, so their preimage commits to the full parameter set (including shares
///      class ID) through the deployer's initialization hash, unlike a reusable factory.
///
///      Computes both child addresses on-chain from class IDs, salts, and constructor args. Both
///      children use this deployer instance (non-universal deploy) so that:
///      1. publish_contract_instance_for_public_execution passes the deployer check
///      2. vault.set_shares_token passes the deployer == msg_sender check
///
///      The SDK must register the same instance preimages with the PXE before deploying this
///      contract so the get_contract_instance oracle can resolve them.
#[aztec]
pub contract VaultDeployer {
    use aztec::{
        hash::hash_args,
        macros::functions::{
            external, initialization_utils::compute_initialization_hash, initializer, internal,
        },
        protocol::{
            abis::function_selector::FunctionSelector, address::AztecAddress,
            contract_class_id::ContractClassId, contract_instance::ContractInstance,
            public_keys::PublicKeys,
        },
        publish_contract_instance::publish_contract_instance_for_public_execution,
    };
    use token_contract::Token;
    use vault_contract::Vault;

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
    #[initializer]
    fn deploy_vault(
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
        let (vault, shares) = self.internal._publish_vault_and_shares_instances(
            asset,
            vault_offset,
            vault_class_id,
            vault_salt,
            shares_name,
            shares_symbol,
            shares_decimals,
            shares_class_id,
            shares_salt,
        );
        self.enqueue(Vault::at(vault).set_shares_token(shares));
    }

    /// @notice Deploys a vault and its shares token atomically, with an initial deposit
    /// @dev The depositor must have authorized the vault to transfer initial_deposit of
    ///      the asset token via authwit before this tx is submitted.
    /// @param asset The underlying asset token address
    /// @param vault_offset The offset used to prevent inflation attacks (typically 1)
    /// @param vault_class_id The contract class ID of the vault contract
    /// @param vault_salt The salt for vault deployment
    /// @param shares_name The name of the shares token
    /// @param shares_symbol The symbol of the shares token
    /// @param shares_decimals The number of decimals for the shares token
    /// @param shares_class_id The contract class ID of the shares token contract
    /// @param shares_salt The salt for shares token deployment
    /// @param initial_deposit The amount of the asset token to deposit into the vault on deployment
    /// @param depositor The address authorizing and funding the initial deposit
    /// @param nonce The authwit nonce authorizing the vault to pull initial_deposit from depositor
    #[external("private")]
    #[initializer]
    fn deploy_vault_with_initial_deposit(
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
        let (vault, shares) = self.internal._publish_vault_and_shares_instances(
            asset,
            vault_offset,
            vault_class_id,
            vault_salt,
            shares_name,
            shares_symbol,
            shares_decimals,
            shares_class_id,
            shares_salt,
        );
        self.enqueue(Vault::at(vault).set_shares_token_with_initial_deposit(
            shares,
            initial_deposit,
            depositor,
            nonce,
        ));
    }

    /// Derives vault and shares addresses, publishes both instances, enqueues their initializers.
    #[internal("private")]
    fn _publish_vault_and_shares_instances(
        asset: AztecAddress,
        vault_offset: u128,
        vault_class_id: ContractClassId,
        vault_salt: Field,
        shares_name: str<31>,
        shares_symbol: str<31>,
        shares_decimals: u8,
        shares_class_id: ContractClassId,
        shares_salt: Field,
    ) -> (AztecAddress, AztecAddress) {
        let vault_constructor = Vault::interface().constructor(asset, vault_offset);
        let vault = _build_instance(
            vault_constructor.selector,
            hash_args(vault_constructor.args),
            vault_class_id,
            vault_salt,
            self.address,
        );

        let shares_constructor = Token::interface().constructor_with_minter(
            shares_name,
            shares_symbol,
            shares_decimals,
            vault,
        );
        let shares = _build_instance(
            shares_constructor.selector,
            hash_args(shares_constructor.args),
            shares_class_id,
            shares_salt,
            self.address,
        );

        publish_contract_instance_for_public_execution(context, vault);
        publish_contract_instance_for_public_execution(context, shares);

        self.enqueue(Vault::at(vault).constructor(asset, vault_offset));
        self.enqueue(Token::at(shares).constructor_with_minter(
            shares_name,
            shares_symbol,
            shares_decimals,
            vault,
        ));

        (vault, shares)
    }

    #[contract_library_method]
    fn _build_instance(
        init_selector: FunctionSelector,
        init_args_hash: Field,
        contract_class_id: ContractClassId,
        salt: Field,
        deployer: AztecAddress,
    ) -> AztecAddress {
        let initialization_hash = compute_initialization_hash(init_selector, init_args_hash);

        ContractInstance {
            salt,
            deployer,
            contract_class_id,
            initialization_hash,
            public_keys: PublicKeys::default(),
        }
            .to_address()
    }
}
