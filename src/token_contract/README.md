# Token Contract

The `Token` contract implements an ERC-20-like token with Aztec-specific privacy extensions. It supports transfers and interactions through both private and public balances, offering full coverage of Aztec's confidentiality features.

This implementation provides a robust foundation for fungible tokens on Aztec, enabling developers to build applications with flexible privacy controls and seamless interoperability between private and public states.

## AIP-20: Aztec Token Standard

This contract follows the [AIP-20 Aztec Token Standard](https://forum.aztec.network/t/request-for-comments-aip-20-aztec-token-standard/7737). Feel free to review and discuss the specification on the Aztec forum.

## AIP-4626: Aztec Tokenized Vault Standard

Optionally, the `Token` contract can be configured as a Tokenized Vault. Learn more [here](#aip-4626-aztec-tokenized-vault-standard-1).

## Storage Fields

- `name: str<31>`: Token name (compressed).
- `symbol: str<31>`: Token symbol (compressed).
- `decimals: u8`: Decimal precision.
- `private_balances: Map<AztecAddress, BalanceSet>`: Private balances per account.
- `public_balances: Map<AztecAddress, u128>`: Public balances per account.
- `total_supply: u128`: Total token supply.
- `minter: AztecAddress`: Authorized minter address (if set).
- `upgrade_authority: AztecAddress`: Address allowed to perform contract upgrades (zero address if not upgradeable).
- `asset: AztecAddress`: Underlying asset address for yield-bearing vault functionality.

## Initializer Functions

### constructor_with_asset
```rust
/// @notice Initializes the token as a yield-bearing vault with an underlying asset
/// @param name The name of the token
/// @param symbol The symbol of the token
/// @param decimals The number of decimals of the token
/// @param asset The address of the underlying asset
/// @param upgrade_authority The address of the upgrade authority (zero if not upgradeable)
#[public]
#[initializer]
fn constructor_with_asset(
    name: str<31>,
    symbol: str<31>,
    decimals: u8,
    asset: AztecAddress,
    upgrade_authority: AztecAddress,
) { /* ... */ }
```

### constructor_with_initial_supply
```rust
/// @notice Initializes the token with an initial supply
/// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
/// @param name The name of the token
/// @param symbol The symbol of the token
/// @param decimals The number of decimals of the token
/// @param initial_supply The initial supply of the token
/// @param to The address to mint the initial supply to
/// @param upgrade_authority The address of the upgrade authority (zero if not upgradeable)
#[public]
#[initializer]
fn constructor_with_initial_supply(
    name: str<31>,
    symbol: str<31>,
    decimals: u8,
    initial_supply: u128,
    to: AztecAddress,
    upgrade_authority: AztecAddress,
) { /* ... */ }
```

### constructor_with_minter
```rust
/// @notice Initializes the token with a minter
/// @param name The name of the token
/// @param symbol The symbol of the token
/// @param decimals The number of decimals of the token
/// @param minter The address of the minter
/// @param upgrade_authority The address of the upgrade authority (zero if not upgradeable)
#[public]
#[initializer]
fn constructor_with_minter(
    name: str<31>,
    symbol: str<31>,
    decimals: u8,
    minter: AztecAddress,
    upgrade_authority: AztecAddress,
) { /* ... */ }
```

## View Functions

### balance_of_public
```rust
/// @notice Returns the public balance of `owner`
/// @param owner The address of the owner
/// @return The public balance of `owner`
#[public]
#[view]
fn balance_of_public(owner: AztecAddress) -> u128 { /* ... */ }
```

### total_supply
```rust
/// @notice Returns the total supply of the token
/// @return The total supply of the token
#[public]
#[view]
fn total_supply() -> u128 { /* ... */ }
```

### name
```rust
/// @notice Returns the name of the token
/// @return The name of the token
#[public]
#[view]
fn name() -> FieldCompressedString { /* ... */ }
```

### symbol
```rust
/// @notice Returns the symbol of the token
/// @return The symbol of the token
#[public]
#[view]
fn symbol() -> FieldCompressedString { /* ... */ }
```

### decimals
```rust
/// @notice Returns the decimals of the token
/// @return The decimals of the token
#[public]
#[view]
fn decimals() -> u8 { /* ... */ }
```

## Utility Functions

### balance_of_private
```rust
/// @notice Returns the private balance of `owner`
/// @param owner The address of the owner
/// @return The private balance of `owner`
#[utility]
unconstrained fn balance_of_private(owner: AztecAddress) -> u128 { /* ... */ }
```

## Public Functions

### transfer_public_to_public
```rust
/// @notice Transfers tokens from public balance to public balance
/// @dev Public call to decrease account balance and a public call to increase recipient balance
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[public]
fn transfer_public_to_public(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_public_to_commitment
```rust
/// @notice Finalizes a transfer of token `amount` from public balance of `from` to a commitment of `to`
/// @dev The transfer must be prepared by calling `initialize_transfer_commitment` first and the resulting
/// `commitment` must be passed as an argument to this function
/// @param from The address of the sender
/// @param commitment The Field representing the commitment (privacy entrance)
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[public]
fn transfer_public_to_commitment(
    from: AztecAddress,
    commitment: Field,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### mint_to_public
```rust
/// @notice Mints tokens to a public balance
/// @dev Increases the public balance of `to` by `amount` and the total supply
/// @param to The address of the recipient
/// @param amount The amount of tokens to mint
#[public]
fn mint_to_public(
    to: AztecAddress,
    amount: u128,
) { /* ... */ }
```

### mint_to_commitment
```rust
/// @notice Finalizes a mint to a commitment
/// @dev Finalizes a mint to a commitment and updates the total supply
/// @param commitment The Field representing the mint commitment (privacy entrance)
/// @param amount The amount of tokens to mint
#[public]
fn mint_to_commitment(
    commitment: Field,
    amount: u128,
) { /* ... */ }
```

### burn_public
```rust
/// @notice Burns tokens from a public balance
/// @dev Burns tokens from a public balance and updates the total supply
/// @param from The address of the sender
/// @param amount The amount of tokens to burn
/// @param nonce The nonce used for authwit
#[public]
fn burn_public(
    from: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### upgrade_contract
```rust
/// @notice Upgrades the contract to a new contract class id
/// @dev Only callable by the `upgrade_authority` and effective after the upgrade delay
/// @param new_contract_class_id The new contract class id
#[public]
fn upgrade_contract(new_contract_class_id: Field) { /* ... */ }
```

## Private Functions

### transfer_private_to_public
```rust
/// @notice Transfer tokens from private balance to public balance
/// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_public(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_private_to_public_with_commitment
```rust
/// @notice Transfer tokens from private balance to public balance with a commitment
/// @dev Spends notes, emits a new note (UintNote) with any remaining change, enqueues a public call, and returns a partial note
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
/// @return commitment The partial note utilized for the transfer commitment (privacy entrance)
#[private]
fn transfer_private_to_public_with_commitment(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) -> Field { /* ... */ }
```

### transfer_private_to_private
```rust
/// @notice Transfer tokens from private balance to private balance
/// @dev Spends notes, emits a new note (UintNote) with any remaining change, and sends a note to the recipient
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_private(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_private_to_commitment
```rust
/// @notice Transfer tokens from private balance to the recipient commitment (recipient must create a commitment first)
/// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
/// @param from The address of the sender
/// @param commitment The Field representing the commitment (privacy entrance that the recipient shares with the sender)
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_commitment(
    from: AztecAddress,
    commitment: Field,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_public_to_private
```rust
/// @notice Transfer tokens from public balance to private balance
/// @dev Enqueues a public call to decrease account balance and emits a new note with balance difference
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_public_to_private(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### initialize_transfer_commitment
```rust
/// @notice Initializes a transfer commitment to be used for transfers/mints
/// @dev Returns a partial note that can be used to execute transfers/mints
/// @param to The address of the recipient
/// @param completer The address used to compute the validity commitment
/// @return commitment The partial note initialized for the transfer/mint commitment
#[private]
fn initialize_transfer_commitment(to: AztecAddress, completer: AztecAddress) -> Field { /* ... */ }
```

### mint_to_private
```rust
/// @notice Mints tokens into a private balance
/// @dev Requires minter, enqueues supply update
/// @param to The address of the recipient
/// @param amount The amount of tokens to mint
#[private]
fn mint_to_private(to: AztecAddress, amount: u128) { /* ... */ }
```

### burn_private
```rust
/// @notice Burns tokens from a private balance
/// @dev Requires authwit, enqueues supply update
/// @param from The address of the sender
/// @param amount The amount of tokens to burn
/// @param nonce The nonce used for authwit
#[private]
fn burn_private(from: AztecAddress, amount: u128, nonce: Field) { /* ... */ }
```

## AIP-4626: Aztec Tokenized Vault Standard

The Token contract (as of now the Tokenized Vault) follows the [AIP-4626: Tokenized Vault Standard](https://forum.aztec.network/t/request-for-comments-aip-4626-tokenized-vault/8079) when configured appropriately. Feel free to review and discuss the specification on the Aztec forum.

## Tokenized Vault Functions

This contract also implements yield-bearing vault functionality when initialized with `constructor_with_asset`. The vault allows users to deposit underlying assets and receive shares representing their proportional ownership of the growing asset pool. The design is an adaptation of the [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626). While the Tokenized Vault contract publicly holds the underlying asset deposits and accrued yield, shares can be held either publicly or privately. Likewise, underlying assets can be deposited from or withdrawn to both public and private balances.

> ⚠️ **WARNING — Private Balance Loss**
>
> any asset tokens transfered to the Tokenized Vault's private balance will be lost forever, as the contract doesn't have keys to spend a private balance nor any recovery mechanism. Yield must be sent to the Vault's public balance.

> ⚠️ **WARNING — Experimental Feature**
>
> the AIP-4626 functionality of this contract is not yet production ready. Use it at your own risk. In particular there is a known overflow issue in the asset<>share conversion logic used on deposits and withdrawals. This can corrupt balances for sufficiently large inputs.

### Function Patterns

Some Tokenized Vault private methods require both `assets` and `shares` amounts as inputs because the exchange rate cannot be computed within the private context. To accommodate this, two complementary patterns are provided:

**Standard Pattern** (e.g., deposit_public_to_private): 
- Exchange rate is provided by the user, giving `assets` and `shares` as inputs.
- Best when exchange rate is known and stable.
- Any slippage or miscalculation will either cause the transaction to revert or leave the difference in favor of the vault (never the user).
- Can be more gas-efficient in certain cases.

**Exact Pattern** (e.g., deposit_public_to_private_exact): 
- Enforces the exact exchange rate at public execution time.
- A portion of the tokens is immediately transferred privately, allowing users to use them in other protocols, while any outstanding or surplus amount is settled privately during public execution via partial notes.
- Best for volatile exchange rates and when slippage could cause significant losses.
- May be more expensive due to the additional settlement logic.

### `max_*` and `preview_*` patterns

Because the vault supports both public and private flows, the `max_*` and `preview_*` families should be interpreted as **helper interfaces** rather than hard guarantees.

**Max Pattern (`max_deposit`, `max_issue`, `max_withdraw`, `max_redeem`)**
- These functions express *policy limits* (caps, pausing, allowlists, etc.) for integrators and frontends.
- In privacy-preserving contexts, these limits are often only *fully enforceable* in **public execution / settlement** (where state and balances can be queried without leaking private information).
- As a result, `max_*` should be treated as **advisory** unless a deployment explicitly enforces them in the relevant public execution path(s).
- Note that `max_withdraw` / `max_redeem` typically only reflect **public share balances** (private holders must track private balances off-chain).

**Preview Pattern (`preview_deposit`, `preview_issue`, `preview_withdraw`, `preview_redeem`)**
- These functions simulate outcomes using the **current public state** (e.g., `total_assets`, `total_supply`) and the same conversion logic as the corresponding operation.
- Previews are intended for quoting and UX; they do not account for private state and do not guarantee execution success if state changes before settlement.
- Previews follow the vault’s rounding rules and therefore may differ slightly from “ideal” real-number math.

> ℹ️ **NOTE — `max_*` and `preview_*` semantics**
>
> The `max_*` functions (`max_deposit`, `max_issue`, `max_withdraw`, `max_redeem`) are exposed as view helpers and are implemented via contract library methods (`_max_*`) so integrators can override policy (caps, pausing, allowlists, etc.).
>
> **Important:** In a privacy-preserving vault, not all entrypoints can safely or deterministically enforce address-dependent limits (e.g. some private flows cannot accept `owner/receiver` without leaking it, and some exchange-rate checks must be performed during public settlement). For this reason, `max_*` should be treated as *advisory* unless a deployment explicitly enforces it in the relevant public execution path(s).
>
> By default, `_max_deposit` and `_max_issue` return `MAX_U128_VALUE` (no limit), while `_max_withdraw` and `_max_redeem` only consider the owner’s **public** share balance.

### Deposit Functions

#### deposit_public_to_public
```rust
/// @notice Deposits underlying assets from public balance and mints shares to public balance
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param assets The amount of underlying assets to deposit
/// @param nonce The nonce used for authwit
#[public]
fn deposit_public_to_public(from: AztecAddress, to: AztecAddress, assets: u128, nonce: Field) { /* ... */ }
```

#### deposit_public_to_private
```rust
/// @notice Deposits underlying assets from public balance and mints shares to private balance
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param assets The amount of underlying assets to deposit
/// @param shares The amount of shares that should be minted to the recipient
/// @param nonce The nonce used for authwit
#[private]
fn deposit_public_to_private(from: AztecAddress, to: AztecAddress, assets: u128, shares: u128, nonce: Field) { /* ... */ }
```

#### deposit_private_to_private
```rust
/// @notice Deposits underlying assets from private balance and mints shares to private balance
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param assets The amount of underlying assets to deposit
/// @param shares The amount of shares that should be minted to the recipient
/// @param nonce The nonce used for authwit
#[private]
fn deposit_private_to_private(from: AztecAddress, to: AztecAddress, assets: u128, shares: u128, nonce: Field) { /* ... */ }
```

#### deposit_private_to_public
```rust
/// @notice Deposits underlying assets from private balance and mints shares to public balance
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param assets The amount of underlying assets to deposit
/// @param nonce The nonce used for authwit
#[private]
fn deposit_private_to_public(from: AztecAddress, to: AztecAddress, assets: u128, nonce: Field) { /* ... */ }
```

### Exact Deposit Functions

#### deposit_public_to_private_exact
```rust
/// @notice Deposits underlying assets from public balance for exact shares to private balance
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param assets The amount of underlying assets to deposit
/// @param min_shares The minimum shares expected to receive
/// @param nonce The nonce used for authwit
#[private]
fn deposit_public_to_private_exact(from: AztecAddress, to: AztecAddress, assets: u128, min_shares: u128, nonce: Field) { /* ... */ }
```

#### deposit_private_to_private_exact
```rust
/// @notice Deposits underlying assets from private balance for exact shares to private balance
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param assets The amount of underlying assets to deposit
/// @param min_shares The minimum shares expected to receive
/// @param nonce The nonce used for authwit
#[private]
fn deposit_private_to_private_exact(from: AztecAddress, to: AztecAddress, assets: u128, min_shares: u128, nonce: Field) { /* ... */ }
```

### Issue Functions

#### issue_public_to_public
```rust
/// @notice Issues exact shares for underlying assets from public balance to public balance
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param shares The exact amount of shares to issue
/// @param max_assets The maximum amount of assets that should be deposited
/// @param nonce The nonce used for authwit
#[public]
fn issue_public_to_public(from: AztecAddress, to: AztecAddress, shares: u128, max_assets: u128, nonce: Field) { /* ... */ }
```

#### issue_public_to_private
```rust
/// @notice Issues exact shares for underlying assets from public balance to private balance
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param shares The exact amount of shares to issue
/// @param max_assets The maximum amount of assets that should be deposited
/// @param nonce The nonce used for authwit
#[private]
fn issue_public_to_private(from: AztecAddress, to: AztecAddress, shares: u128, max_assets: u128, nonce: Field) { /* ... */ }
```

#### issue_private_to_public_exact
```rust
/// @notice Issues exact shares for underlying assets from private balance to public balance
/// @dev Any excess assets transferred in private will be returned via commitment during public execution
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param shares The exact amount of shares to issue
/// @param max_assets The maximum amount of assets that should be deposited
/// @param nonce The nonce used for authwit
#[private]
fn issue_private_to_public_exact(from: AztecAddress, to: AztecAddress, shares: u128, max_assets: u128, nonce: Field) { /* ... */ }
```

#### issue_private_to_private_exact
```rust
/// @notice Issues exact shares for underlying assets from private balance to private balance
/// @dev Any excess assets transferred in private will be returned via commitment during public execution
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param shares The exact amount of shares to issue
/// @param max_assets The maximum amount of assets that should be deposited
/// @param nonce The nonce used for authwit
#[private]
fn issue_private_to_private_exact(from: AztecAddress, to: AztecAddress, shares: u128, max_assets: u128, nonce: Field) { /* ... */ }
```

### Withdraw Functions

#### withdraw_public_to_public
```rust
/// @notice Withdraws underlying assets by burning shares from public balance to public balance
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param assets The amount of underlying assets to withdraw
/// @param nonce The nonce used for authwit
#[public]
fn withdraw_public_to_public(from: AztecAddress, to: AztecAddress, assets: u128, nonce: Field) { /* ... */ }
```

#### withdraw_public_to_private
```rust
/// @notice Withdraws underlying assets by burning shares from public balance to private balance
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param assets The amount of underlying assets to withdraw
/// @param nonce The nonce used for authwit
#[private]
fn withdraw_public_to_private(from: AztecAddress, to: AztecAddress, assets: u128, nonce: Field) { /* ... */ }
```

#### withdraw_private_to_private
```rust
/// @notice Withdraws underlying assets by burning shares from private balance to private balance
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param assets The amount of underlying assets to withdraw
/// @param shares The amount of shares to burn
/// @param nonce The nonce used for authwit
#[private]
fn withdraw_private_to_private(from: AztecAddress, to: AztecAddress, assets: u128, shares: u128, nonce: Field) { /* ... */ }
```

#### withdraw_private_to_public_exact
```rust
/// @notice Withdraws exact underlying assets by burning shares from private balance to public balance
/// @dev Excess shares transferred in private will be returned via commitment during public execution
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param assets The amount of underlying assets to withdraw
/// @param max_shares The maximum amount of shares to burn
/// @param nonce The nonce used for authwit
#[private]
fn withdraw_private_to_public_exact(from: AztecAddress, to: AztecAddress, assets: u128, max_shares: u128, nonce: Field) { /* ... */ }
```

#### withdraw_private_to_private_exact
```rust
/// @notice Withdraws exact underlying assets by burning shares from private balance to private balance
/// @dev Excess shares transferred in private will be returned via commitment during public execution
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param assets The amount of underlying assets to withdraw
/// @param max_shares The maximum amount of shares to burn
/// @param nonce The nonce used for authwit
#[private]
fn withdraw_private_to_private_exact(from: AztecAddress, to: AztecAddress, assets: u128, max_shares: u128, nonce: Field) { /* ... */ }
```

### Redeem Functions

#### redeem_public_to_public
```rust
/// @notice Redeems shares for underlying assets from public balance to public balance
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param shares The amount of shares to redeem
/// @param nonce The nonce used for authwit
#[public]
fn redeem_public_to_public(from: AztecAddress, to: AztecAddress, shares: u128, nonce: Field) { /* ... */ }
```

#### redeem_private_to_public
```rust
/// @notice Redeems shares for underlying assets from private balance to public balance
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param shares The amount of shares to redeem
/// @param nonce The nonce used for authwit
#[private]
fn redeem_private_to_public(from: AztecAddress, to: AztecAddress, shares: u128, nonce: Field) { /* ... */ }
```

#### redeem_private_to_private_exact
```rust
/// @notice Redeems shares for exact underlying assets from private balance to private balance
/// @dev Outstanding assets beyond min_assets will be transferred via commitment during public execution
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param shares The amount of shares to redeem
/// @param min_assets The minimum amount of assets to withdraw immediately in private
/// @param nonce The nonce used for authwit
#[private]
fn redeem_private_to_private_exact(from: AztecAddress, to: AztecAddress, shares: u128, min_assets: u128, nonce: Field) { /* ... */ }
```

#### redeem_public_to_private_exact
```rust
/// @notice Redeems shares for exact underlying assets from public balance to private balance
/// @dev Outstanding assets beyond min_assets will be transferred via commitment during public execution
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param shares The amount of shares to redeem
/// @param min_assets The minimum amount of assets to withdraw immediately in private
/// @param nonce The nonce used for authwit
#[private]
fn redeem_public_to_private_exact(from: AztecAddress, to: AztecAddress, shares: u128, min_assets: u128, nonce: Field) { /* ... */ }
```

### Vault View Functions

#### asset
```rust
/// @notice Returns the underlying asset address
/// @return The address of the underlying asset
#[public]
#[view]
fn asset() -> AztecAddress { /* ... */ }
```

#### total_assets
```rust
/// @notice Returns the total amount of underlying assets held by the vault
/// @return The total amount of assets held by the vault
#[public]
#[view]
fn total_assets() -> u128 { /* ... */ }
```

#### convert_to_shares
```rust
/// @notice Converts an amount of assets to shares using the current exchange rate
/// @param assets The amount of assets to convert
/// @return The equivalent amount of shares
#[public]
#[view]
fn convert_to_shares(assets: u128) -> u128 { /* ... */ }
```

#### convert_to_assets
```rust
/// @notice Converts an amount of shares to assets using the current exchange rate
/// @param shares The amount of shares to convert
/// @return The equivalent amount of assets
#[public]
#[view]
fn convert_to_assets(shares: u128) -> u128 { /* ... */ }
```

#### max_deposit
```rust
/// @notice Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver
/// @param receiver The address of the receiver
/// @return The maximum amount of assets that can be deposited
#[public]
#[view]
fn max_deposit(receiver: AztecAddress) -> u128 { /* ... */ }
```

#### preview_deposit
```rust
/// @notice Simulates the effects of a deposit at the current block
/// @param assets The amount of assets to deposit
/// @return The amount of shares that would be minted
#[public]
#[view]
fn preview_deposit(assets: u128) -> u128 { /* ... */ }
```

#### max_issue
```rust
/// @notice Returns the maximum amount of Vault shares that can be issued for the receiver
/// @param receiver The address of the receiver
/// @return The maximum amount of shares that can be issued
#[public]
#[view]
fn max_issue(receiver: AztecAddress) -> u128 { /* ... */ }
```

#### preview_issue
```rust
/// @notice Simulates the effects of an issue at the current block
/// @param shares The amount of shares to issue
/// @return The amount of assets required to issue the shares
#[public]
#[view]
fn preview_issue(shares: u128) -> u128 { /* ... */ }
```

#### max_withdraw
```rust
/// @notice Returns the maximum amount of the underlying asset that can be withdrawn from the owner's public balance
/// @dev This does NOT include private balance - private holders must track their own balance
/// @param owner The address of the owner
/// @return The maximum amount of assets that can be withdrawn
#[public]
#[view]
fn max_withdraw(owner: AztecAddress) -> u128 { /* ... */ }
```

#### preview_withdraw
```rust
/// @notice Simulates the effects of a withdrawal at the current block
/// @param assets The amount of assets to withdraw
/// @return The amount of shares that would be burned
#[public]
#[view]
fn preview_withdraw(assets: u128) -> u128 { /* ... */ }
```

#### max_redeem
```rust
/// @notice Returns the maximum amount of Vault shares that can be redeemed from the owner's public balance
/// @dev This does NOT include private balance - private holders must track their own balance
/// @param owner The address of the owner
/// @return The maximum amount of shares that can be redeemed
#[public]
#[view]
fn max_redeem(owner: AztecAddress) -> u128 { /* ... */ }
```

#### preview_redeem
```rust
/// @notice Simulates the effects of a redemption at the current block
/// @param shares The amount of shares to redeem
/// @return The amount of assets that would be received
#[public]
#[view]
fn preview_redeem(shares: u128) -> u128 { /* ... */ }
```

### Vault Contract Library Methods

### Conversion Functions

#### _total_assets
```rust
/// @notice Returns the total amount of underlying assets held by the vault
/// @param context The public context
/// @param asset The storage pointer to the asset address
/// @return The total amount of assets held by the vault
#[contract_library_method]
unconstrained fn _total_assets(
    context: &mut PublicContext,
    asset: PublicImmutable<AztecAddress, &mut PublicContext>,
) -> u128 { /* ... */ }
```

#### _convert_to_shares
```rust
/// @notice Converts an amount of assets to shares using the current exchange rate
/// @param assets The amount of assets to convert
/// @param total_assets The total amount of assets in the vault
/// @param total_supply The storage pointer to the total supply of shares
/// @param rounding The rounding direction (ROUND_UP or ROUND_DOWN)
/// @return The equivalent amount of shares
#[contract_library_method]
fn _convert_to_shares(
    assets: u128,
    total_assets: u128,
    total_supply: PublicMutable<u128, &mut PublicContext>,
    rounding: bool,
) -> u128 { /* ... */ }
```

#### _convert_to_assets
```rust
/// @notice Converts an amount of shares to assets using the current exchange rate
/// @param shares The amount of shares to convert
/// @param total_assets The total amount of assets in the vault
/// @param total_supply The storage pointer to the total supply of shares
/// @param rounding The rounding direction (ROUND_UP or ROUND_DOWN)
/// @return The equivalent amount of assets
#[contract_library_method]
fn _convert_to_assets(
    shares: u128,
    total_assets: u128,
    total_supply: PublicMutable<u128, &mut PublicContext>,
    rounding: bool,
) -> u128 { /* ... */ }
```

#### offset
```rust
/// @notice Offset that determines the rate of virtual shares to virtual assets in the vault
/// @dev While not fully preventing inflation attacks, analysis shows that offset=1 makes it non-profitable 
///      even if an attacker is able to capture value from multiple user deposits.
///      With a larger offset, the attack becomes orders of magnitude more expensive than it is profitable.
/// @return The offset value
#[contract_library_method]
fn offset() -> u128 { /* ... */ }
```

### Max Functions

#### _max_deposit
```rust
/// @dev Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver, through a deposit call.
/// @dev The receiver parameter is accepted for ERC-4626 compatibility and future extensibility, but is not used by the default implementation.
/// @param _receiver The address of the receiver
/// @return The maximum amount of assets that can be deposited
#[contract_library_method]
fn _max_deposit(_receiver: AztecAddress) -> u128 { /* ... */ }
```

#### _max_issue
```rust
/// @dev Returns the maximum amount of the Vault shares that can be issued for the receiver, through a mint call.
/// @dev The receiver parameter is accepted for ERC-4626 compatibility and future extensibility, but is not used by the default implementation.
/// @param _receiver The address of the receiver
/// @return The maximum amount of shares that can be issued
#[contract_library_method]
fn _max_issue(_receiver: AztecAddress) -> u128 { /* ... */ }
```

#### _max_withdraw
```rust
/// @dev Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the Vault, through a withdraw call.
/// @notice This does NOT include private balance - private holders must track their own balance.
/// @param owner The address of the owner
/// @param context The context of the public call
/// @param public_balances The storage pointer to the public balance
/// @param asset The storage pointer to the asset address
/// @param total_supply The storage pointer to the total supply
/// @return The maximum amount of assets that can be withdrawn
#[contract_library_method]
unconstrained fn _max_withdraw(
    owner: AztecAddress,
    context: &mut PublicContext,
    public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
    asset: PublicImmutable<AztecAddress, &mut PublicContext>,
    total_supply: PublicMutable<u128, &mut PublicContext>,
) -> u128 { /* ... */ }
```

#### _max_redeem
```rust
/// @dev Returns the maximum amount of the Vault shares that can be redeemed from the owner balance in the Vault, through a redeem call.
/// @notice This does NOT include private balance - private holders must track their own balance.
/// @param owner The address of the owner
/// @return The maximum amount of shares that can be redeemed
#[contract_library_method]
fn _max_redeem(
    owner: AztecAddress,
    public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
) -> u128 { /* ... */ }
```

### Preview Functions

#### _preview_deposit
```rust
/// @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given current on-chain conditions.
/// @param assets The amount of assets to deposit
/// @param context The context of the public call
/// @param asset The storage pointer to the asset address
/// @param total_supply The storage pointer to the total supply
/// @return The amount of shares that would be minted
#[contract_library_method]
unconstrained fn _preview_deposit(
    assets: u128,
    context: &mut PublicContext,
    asset: PublicImmutable<AztecAddress, &mut PublicContext>,
    total_supply: PublicMutable<u128, &mut PublicContext>,
) -> u128 { /* ... */ }
```

#### _preview_issue
```rust
/// @dev Allows an on-chain or off-chain user to simulate the effects of their issue at the current block, given current on-chain conditions.
/// @param shares The amount of shares to deposit
/// @param context The context of the public call
/// @param asset The storage pointer to the asset address
/// @param total_supply The storage pointer to the total supply
/// @return The amount of assets that would be issued
#[contract_library_method]
unconstrained fn _preview_issue(
    shares: u128,
    context: &mut PublicContext,
    asset: PublicImmutable<AztecAddress, &mut PublicContext>,
    total_supply: PublicMutable<u128, &mut PublicContext>,
) -> u128 { /* ... */ }
```

#### _preview_withdraw
```rust
/// @dev Allows an on-chain or off-chain user to simulate the effects of their withdraw at the current block, given current on-chain conditions.
/// @param assets The amount of assets to withdraw
/// @param context The context of the public call
/// @param asset The storage pointer to the asset address
/// @param total_supply The storage pointer to the total supply
/// @return The amount of shares that would be redeemed
#[contract_library_method]
unconstrained fn _preview_withdraw(
    assets: u128,
    context: &mut PublicContext,
    asset: PublicImmutable<AztecAddress, &mut PublicContext>,
    total_supply: PublicMutable<u128, &mut PublicContext>,
) -> u128 { /* ... */ }
```

#### _preview_redeem
```rust
/// @dev Allows an on-chain or off-chain user to simulate the effects of their redeem at the current block, given current on-chain conditions.
/// @param shares The amount of shares to redeem
/// @param context The context of the public call
/// @param asset The storage pointer to the asset address
/// @param total_supply The storage pointer to the total supply
/// @return The amount of assets that would be redeemed
#[contract_library_method]
unconstrained fn _preview_redeem(
    shares: u128,
    context: &mut PublicContext,
    asset: PublicImmutable<AztecAddress, &mut PublicContext>,
    total_supply: PublicMutable<u128, &mut PublicContext>,
) -> u128 { /* ... */ }
```
