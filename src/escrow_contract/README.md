# Escrow Standard

The Escrow Standard defines a minimal, reusable on-chain Escrow contract that safely holds private balances while delegating release logic, key distribution, and participant discovery to a separate Logic contract. 

Since encryption and nullification keys are needed to read and spend private balances, respectively, the Escrow contract must have keys. A single secret key is used to derive all master secret keys and public keys internally. Logic contracts should implement a key- and escrow-sharing mechanism, for which a Logic library with helper functions is provided.

Logic contract implementations may vary greatly among use cases, but the basic patterns presented here, available in the logic library, should be used carefully, so that privacy is preserved. Examples of logic contracts can be found [here](https://github.com/defi-wonderland/aztec-escrow-extensions).

## Escrow Contract

The Escrow contract is a minimally designed private contract with the following important characteristics:
- Needs to be setup with keys. This allows the Escrow to hold private balances.
- Does not need to be publicly deployed.
- Has only two methods - `withdraw()` and `withdraw_nft()` - that allows the owner of the Escrow to spend private balances of tokens or NFTs compliant with AIP-20 and AIP-721, respectively. The keys are needed for these.
- Is fully private. Tokens and NFTs can only be withdrawn from the Escrow to another private balance, which does not leak any information.
- Only the owner can interact with the Escrow.
- Does not have storage nor needs initialization. The owner of the Escrow is defined as an `AztecAddress` encoded into the contract instance salt, which means that its immutable and the Escrow address is determined by it.

## Private Functions

### withdraw
```rust
/// @notice Withdraws an amount from the escrow's private balance to the
///         recipient's private balance.
/// @dev Can only be called by the corresponding Logic contract
/// @param token The address of the token
/// @param amount The amount of tokens to withdraw from the escrow
/// @param recipient The address of the recipient
#[private]
fn withdraw(token: AztecAddress, amount: u128, recipient: AztecAddress) { /* ... */ }
```

### withdraw_nft
```rust
/// @notice Withdraws a token of a given ID from the escrow's private balance to
///         the recipient's private balance
/// @dev Can only be called by the corresponding Logic contract
/// @param nft The address of the NFT contract
/// @param token_id The id of the token to withdraw from the escrow
/// @param recipient The address of the recipient
#[private]
fn withdraw_nft(nft: AztecAddress, token_id: Field, recipient: AztecAddress) { /* ... */ }
```

## Logic Library

The Logic library provides functions that standardize and facilitate the implementation of Logic contracts. We call Logic contract any contract that owns one or multiple Escrows. Unlike the Escrow contract, a Logic contract implements the policy for a specific escrow use case and therefore can vary significantly between applications. For example, a trivial Logic that always releases tokens needs a much simpler interface than one that supports clawbacks, vesting schedules, or milestone conditions.

Usually, a Logic contract will have the following features:

- Manages how escrow details, including keys, are shared to escrow's participants.
- Ensures that the escrow details are valid.
- Assigns roles to participants (recipients, owner, etc.) and set any additional conditions (start timestamps, amounts, expiration, etc.).
- Manages Escrow withdrawals.

## Library Functions

The library functions guarantee that escrow's keys, contract class ID and setup are correct while standardizing the correct private sharing of keys and escrow address to participants. 

> ⚠️ **WARNING — Private Balance Loss**
>
> It's still the job of the Logic contract implementation to handle information safely and privately, while avoiding malicious attempts of withdrawing funds from Escrow contracts. This library facilitates this but cannot ensure Logic contracts are implemented correctly. Use carefully.

### _get_escrow
```rust
/// @notice Returns the escrow address that corresponds to the given secret key and class ID.
/// @param context The private context
/// @param escrow_class_id The contract class id of the escrow contract
/// @param secret_key The secret key used to derive master secret keys and public keys
/// @return The escrow address
#[contract_library_method]
pub fn _get_escrow(
    context: &mut PrivateContext,
    escrow_class_id: Field,
    secret_key: Field,
) { /* ... */ }
```

### _share_escrow
```rust
/// @notice Shares the escrow details needed to find and use the escrow contract
/// @dev Emits a private log with the escrow details
/// @param context The private context
/// @param account The address of the account that will use the escrow
/// @param escrow The address of the escrow
/// @param secret_key The secret key used to derive master secret keys and public keys
#[contract_library_method]
pub fn _share_escrow(
    context: &mut PrivateContext,
    account: AztecAddress,
    escrow: AztecAddress,
    secret_key: Field,
) { /* ... */ }
```

### _withdraw
```rust
/// @notice Withdraws an amount of tokens from the provided escrow.
/// @param context The private context
/// @param escrow The address of the escrow
/// @param account The address of the account that will receive the tokens
/// @param token The address of the token
/// @param amount The amount of tokens to withdraw from the escrow
#[contract_library_method]
pub fn _withdraw(
    context: &mut PrivateContext,
    escrow: AztecAddress,
    account: AztecAddress,
    token: AztecAddress,
    amount: u128,
) { /* ... */ }
```

### _withdraw_nft
```rust
/// @notice Withdraws an NFT from the provided escrow.
/// @param context The private context
/// @param escrow The address of the escrow
/// @param account The address of the account that will receive the NFT
/// @param nft The address of the NFT contract
/// @param token_id The id of the token to withdraw from the escrow
#[contract_library_method]
pub fn _withdraw_nft(
    context: &mut PrivateContext,
    escrow: AztecAddress,
    account: AztecAddress,
    nft: AztecAddress,
    token_id: Field,
){ /* ... */ }
```

## Key Derivation Module

> **Warning**
> The key derivation module depends on [noir-lang/sha512](https://github.com/noir-lang/sha512), which has not been reviewed by the Noir team and is unaudited. Use at your own risk.

The escrow contract includes a standalone `key_derivation` module that replicates the Aztec protocol's key derivation pipeline entirely in Noir. This allows the escrow contract to derive all master secret keys and public keys from a single `secret_key: Field`, without depending on the PXE or any external key management.

This is critical because:
- The PXE requires the secret key — not the derived master secret keys — to register an account.
- Logic contracts need to compute the escrow's public keys to derive its address, but must not leak the secret key publicly.
- By performing derivation on-chain in Noir, the secret key never leaves the private context.

### Derivation Pipeline

The pipeline matches the Aztec protocol's `deriveKeys` implementation. Each master secret key is derived by hashing the secret key concatenated with a domain separator, then reducing the 512-bit result modulo the Grumpkin scalar field (BN254 Fq). Public keys are derived via fixed-base scalar multiplication on the Grumpkin curve.

```
secret_key (Field)
    ├── SHA512(sk || DOM_SEP__NHK_M)  mod Fq  →  nhk_m  →  npk_m
    ├── SHA512(sk || DOM_SEP__IVSK_M) mod Fq  →  ivsk_m →  ivpk_m
    ├── SHA512(sk || DOM_SEP__OVSK_M) mod Fq  →  ovsk_m →  ovpk_m
    └── SHA512(sk || DOM_SEP__TSK_M)  mod Fq  →  tsk_m  →  tpk_m
```

### Usage

```rust
use escrow_contract::key_derivation::{secret_key_to_public_keys, derive_keys, MasterSecretKeys};

// Full pipeline: secret key → public keys
let public_keys: PublicKeys = secret_key_to_public_keys(secret_key);

// Or derive intermediate master secret keys
let msks: MasterSecretKeys = derive_keys(secret_key);
```

### Public Functions

#### secret_key_to_public_keys
```rust
/// @notice Derives public keys from a secret key (full pipeline: sk -> msks -> pks).
/// @param secret_key The secret key
/// @return PublicKeys containing the derived public keys.
pub fn secret_key_to_public_keys(secret_key: Field) -> PublicKeys { /* ... */ }
```

#### derive_keys
```rust
/// @notice Derive all four master secret keys from a secret key.
/// @param secret_key The secret key
/// @return MasterSecretKeys containing nhk_m, ivsk_m, ovsk_m, tsk_m.
pub fn derive_keys(secret_key: Field) -> MasterSecretKeys { /* ... */ }
```

#### master_secret_keys_to_public_keys
```rust
/// @notice Derives public keys from master secret keys.
/// @param master_secret_keys The master secret keys
/// @return PublicKeys containing the derived public keys.
pub fn master_secret_keys_to_public_keys(master_secret_keys: MasterSecretKeys) -> PublicKeys { /* ... */ }
```
