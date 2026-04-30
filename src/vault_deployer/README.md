# Vault Deployer Contract

The `VaultDeployer` is a disposable contract that atomically deploys and wires a [`Vault`](../vault_contract) together with its AIP-20 shares [`Token`](../token_contract) in a single transaction, working around the two-step initialization the vault would otherwise require (see the vault [Deployment Guide](../vault_contract/README.md#deployment-guide)).

## Why a per-vault deployer instance?

`publish_contract_instance_for_public_execution` is private-only, so a reusable public factory can't deploy and link both contracts in one step until [public instance registration](https://github.com/AztecProtocol/aztec-packages/issues/20771) lands.

Instead, each vault gets its own fresh `VaultDeployer` instance whose private initializer runs once and:

1. Derives the vault and shares addresses on-chain from their class IDs, the deployer instance's salt, and constructor args (with this deployer instance set as their `deployer`).
2. Calls `publish_contract_instance_for_public_execution` for both.
3. Enqueues the vault constructor and the shares-token `constructor_with_minter` (with the vault as minter).
4. Enqueues `set_shares_token` (or `set_shares_token_with_initial_deposit`) on the vault.

The vault's deployer-of-instance check on `set_shares_token*` ensures only this `VaultDeployer` instance can perform the link.

## Initializer Functions

### deploy_vault

```rust
/// @notice Deploys a vault and its shares token atomically
/// @param asset The underlying asset token address
/// @param vault_offset The offset used to prevent inflation attacks (typically 1)
/// @param vault_class_id The contract class ID of the vault contract
/// @param shares_name The name of the shares token
/// @param shares_symbol The symbol of the shares token
/// @param shares_decimals The number of decimals for the shares token
/// @param shares_class_id The contract class ID of the shares token contract
#[private]
#[initializer]
fn deploy_vault(
    asset: AztecAddress,
    vault_offset: u128,
    vault_class_id: ContractClassId,
    shares_name: str<31>,
    shares_symbol: str<31>,
    shares_decimals: u8,
    shares_class_id: ContractClassId,
) { /* ... */ }
```

### deploy_vault_with_initial_deposit

```rust
/// @notice Deploys a vault and its shares token atomically, with an initial deposit for inflation-attack protection
/// @dev The depositor must have authorized the vault to transfer initial_deposit of the asset token via authwit before this tx is submitted.
/// @param asset The underlying asset token address
/// @param vault_offset The offset used to prevent inflation attacks (typically 1)
/// @param vault_class_id The contract class ID of the vault contract
/// @param shares_name The name of the shares token
/// @param shares_symbol The symbol of the shares token
/// @param shares_decimals The number of decimals for the shares token
/// @param shares_class_id The contract class ID of the shares token contract
/// @param initial_deposit The amount of the asset token to deposit into the vault on deployment
/// @param depositor The address authorizing and funding the initial deposit
/// @param nonce The authwit nonce authorizing the vault to pull initial_deposit from depositor
#[private]
#[initializer]
fn deploy_vault_with_initial_deposit(
    asset: AztecAddress,
    vault_offset: u128,
    vault_class_id: ContractClassId,
    shares_name: str<31>,
    shares_symbol: str<31>,
    shares_decimals: u8,
    shares_class_id: ContractClassId,
    initial_deposit: u128,
    depositor: AztecAddress,
    nonce: Field,
) { /* ... */ }
```

## Usage Notes

- Publish the `Vault` and `Token` contract classes once per network before deploying any `VaultDeployer` instance.
- The SDK must register the vault and shares contract instance preimages with the PXE before submitting the deployer transaction so the `get_contract_instance` oracle can resolve them.
- Both the vault and shares contract instances use the `VaultDeployer` instance as their `deployer` and reuse its salt as their own salt. Their addresses can therefore be precomputed off-chain from the `VaultDeployer` instance address, the `VaultDeployer` instance salt, the corresponding `ContractClassId` (vault or shares), and the corresponding initialization hash (derived from the constructor selector and args). Precomputing the vault address is required when using `deploy_vault_with_initial_deposit` so the depositor can sign an authwit for the asset transfer to the vault.
