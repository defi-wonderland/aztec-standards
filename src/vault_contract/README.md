# Vault Contract

The `Vault` contract is a standalone yield-bearing vault that holds an underlying AIP-20 asset and issues AIP-20 share tokens to depositors. The vault and shares token are separate contracts — the vault manages deposit/withdraw/redeem logic while delegating share token operations (mint, burn, transfer) to an external AIP-20 `Token` contract configured with the vault as its minter.

This vault is **inspired by** [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) but **diverges substantially** from it. In particular, the share token is a **separate AIP-20 contract** rather than the vault itself — a structure closer in spirit to [ERC-7575](https://eips.ethereum.org/EIPS/eip-7575), which decouples the share token from the vault entrypoint. On top of that, Aztec's privacy model adds capabilities that have no counterpart in either standard: the vault publicly holds the underlying asset deposits and accrued yield, but shares can be held either publicly or privately, and underlying assets can be deposited from or withdrawn to both public and private balances.

## AIP-4626: Aztec Tokenized Vault Standard

This contract follows the [AIP-4626: Tokenized Vault Standard](https://forum.aztec.network/t/request-for-comments-aip-4626-tokenized-vault/8079). Feel free to review and discuss the specification on the Aztec forum.

> **WARNING — Private Balance Loss**
>
> Any asset tokens transferred to the Vault's private balance will be lost forever, as the contract doesn't have keys to spend a private balance nor any recovery mechanism. Yield must be sent to the Vault's public balance.

<!-- -->

> **WARNING — Experimental Feature**
>
> The AIP-4626 functionality of this contract is not yet production-ready. Use it at your own risk. In particular there is a known overflow issue in the asset<>share conversion logic used on deposits and withdrawals. This can corrupt balances for sufficiently large inputs.

## Architecture

Unlike the previous design where vault functionality was embedded in the Token contract, the `Vault` is now a standalone contract that references two external AIP-20 Token contracts:

- **Asset token**: The underlying AIP-20 token being deposited into the vault.
- **Shares token**: A separate AIP-20 token whose minter is the vault. The vault mints/burns shares to represent depositor ownership.

This separation enables cleaner composability — the shares token is a standard AIP-20 token that can be used in any protocol that accepts AIP-20 tokens.

## Storage Fields

- `asset: AztecAddress`: The underlying asset token address.
- `shares: AztecAddress`: The shares token address (set post-deployment via `set_shares_token`).
- `vault_offset: u128`: Offset used to prevent inflation attacks.

## Initializer Functions

### constructor

```rust
/// @notice Initializes the vault with asset and offset
/// @dev The deployer must call set_shares_token() after deploying the shares token with this vault as minter.
///      The vault must NOT use universal deploy (deployer must be non-zero) so the deployer address can
///      authorize set_shares_token calls.
/// @param asset The underlying asset token address
/// @param vault_offset The offset used to prevent inflation attacks (typically 1)
#[public]
#[initializer]
fn constructor(asset: AztecAddress, vault_offset: u128) { /* ... */ }
```

## Setup Functions

### set_shares_token

```rust
/// @notice Sets the shares token address (one-time, deployer-only, immutable after set)
/// @dev Must be called after deploying the shares token with this vault as minter.
///      Only the contract deployer (from the contract instance) can call this.
///      PublicImmutable.initialize() ensures this can only ever be set once.
///      All vault operations revert until this is called.
/// @param shares The shares token address (minter must be this vault)
#[public]
fn set_shares_token(shares: AztecAddress) { /* ... */ }
```

### set_shares_token_with_initial_deposit

```rust
/// @notice Sets the shares token and makes an initial deposit for inflation-attack protection
/// @dev Must be called after deploying the shares token with this vault as minter.
///      Only the contract deployer (from the contract instance) can call this.
///      PublicImmutable.initialize() ensures this can only ever be set once.
///      All vault operations revert until this is called.
/// @param shares The shares token address (minter must be this vault)
/// @param initial_deposit The initial deposit amount of the asset
/// @param depositor The address of the initial depositor of the assets
/// @param nonce The nonce used for authwitness for the transfer of the initial deposit
#[public]
fn set_shares_token_with_initial_deposit(
    shares: AztecAddress,
    initial_deposit: u128,
    depositor: AztecAddress,
    nonce: Field,
) { /* ... */ }
```

## Function Patterns

Some Vault private methods require both `assets` and `shares` amounts as inputs because the exchange rate cannot be computed within the private context. To accommodate this, two complementary patterns are provided:

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
- Previews follow the vault's rounding rules and reflect the amounts that would be computed at public execution time under current on-chain state.

### Privacy leaks

In the current implementation the functions `deposit_public_to_private`, `deposit_public_to_private_exact`, `issue_public_to_private`, `withdraw_public_to_private` and `redeem_public_to_private_exact` can leak the `to` address. Although they are private functions, all other input parameters become public during execution, which allows an attacker to brute-force candidate `to` addresses until finding one that matches the authwit hash. This limitation will be addressed in a future update.

Also note that several other functions rely on unpredictable nonces for privacy. If private nonces are guessable or reused, additional operations could become vulnerable to similar privacy leaks. Always ensure nonces are generated in a way that is infeasible to predict.

## Deposit Functions

### deposit_public_to_public

```rust
/// @notice Deposits underlying assets from public balance and mints shares to public balance
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param assets The amount of underlying assets to deposit
/// @param nonce The nonce used for authwit
#[public]
fn deposit_public_to_public(from: AztecAddress, to: AztecAddress, assets: u128, nonce: Field) { /* ... */ }
```

### deposit_public_to_private

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

### deposit_private_to_private

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

### deposit_private_to_public

```rust
/// @notice Deposits underlying assets from private balance and mints shares to public balance
/// @param from The address providing the assets
/// @param to The address receiving the shares
/// @param assets The amount of underlying assets to deposit
/// @param nonce The nonce used for authwit
#[private]
fn deposit_private_to_public(from: AztecAddress, to: AztecAddress, assets: u128, nonce: Field) { /* ... */ }
```

## Exact Deposit Functions

### deposit_public_to_private_exact

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

### deposit_private_to_private_exact

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

## Issue Functions

### issue_public_to_public

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

### issue_public_to_private

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

### issue_private_to_public_exact

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

### issue_private_to_private_exact

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

## Withdraw Functions

### withdraw_public_to_public

```rust
/// @notice Withdraws underlying assets by burning shares from public balance to public balance
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param assets The amount of underlying assets to withdraw
/// @param nonce The nonce used for authwit
#[public]
fn withdraw_public_to_public(from: AztecAddress, to: AztecAddress, assets: u128, nonce: Field) { /* ... */ }
```

### withdraw_public_to_private

```rust
/// @notice Withdraws underlying assets by burning shares from public balance to private balance
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param assets The amount of underlying assets to withdraw
/// @param nonce The nonce used for authwit
#[private]
fn withdraw_public_to_private(from: AztecAddress, to: AztecAddress, assets: u128, nonce: Field) { /* ... */ }
```

### withdraw_private_to_private

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

### withdraw_private_to_public_exact

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

### withdraw_private_to_private_exact

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

## Redeem Functions

### redeem_public_to_public

```rust
/// @notice Redeems shares for underlying assets from public balance to public balance
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param shares The amount of shares to redeem
/// @param nonce The nonce used for authwit
#[public]
fn redeem_public_to_public(from: AztecAddress, to: AztecAddress, shares: u128, nonce: Field) { /* ... */ }
```

### redeem_private_to_public

```rust
/// @notice Redeems shares for underlying assets from private balance to public balance
/// @param from The address providing the shares
/// @param to The address receiving the assets
/// @param shares The amount of shares to redeem
/// @param nonce The nonce used for authwit
#[private]
fn redeem_private_to_public(from: AztecAddress, to: AztecAddress, shares: u128, nonce: Field) { /* ... */ }
```

### redeem_private_to_private_exact

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

### redeem_public_to_private_exact

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

## View Functions

### asset

```rust
/// @notice Returns the underlying asset address
/// @return The address of the underlying asset
#[public]
#[view]
fn asset() -> AztecAddress { /* ... */ }
```

### shares

```rust
/// @notice Returns the shares token address
/// @return The address of the shares token
#[public]
#[view]
fn shares() -> AztecAddress { /* ... */ }
```

### total_assets

```rust
/// @notice Returns the total amount of underlying assets held by the vault
/// @return The total amount of assets held by the vault
#[public]
#[view]
fn total_assets() -> u128 { /* ... */ }
```

### convert_to_shares

```rust
/// @notice Converts an amount of assets to shares using the current exchange rate
/// @param assets The amount of assets to convert
/// @return The equivalent amount of shares
#[public]
#[view]
fn convert_to_shares(assets: u128) -> u128 { /* ... */ }
```

### convert_to_assets

```rust
/// @notice Converts an amount of shares to assets using the current exchange rate
/// @param shares The amount of shares to convert
/// @return The equivalent amount of assets
#[public]
#[view]
fn convert_to_assets(shares: u128) -> u128 { /* ... */ }
```

### max_deposit

```rust
/// @notice Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver
/// @param receiver The address of the receiver
/// @return The maximum amount of assets that can be deposited
#[public]
#[view]
fn max_deposit(receiver: AztecAddress) -> u128 { /* ... */ }
```

### preview_deposit

```rust
/// @notice Simulates the effects of a deposit at the current block
/// @param assets The amount of assets to deposit
/// @return The amount of shares that would be minted
#[public]
#[view]
fn preview_deposit(assets: u128) -> u128 { /* ... */ }
```

### max_issue

```rust
/// @notice Returns the maximum amount of Vault shares that can be issued for the receiver
/// @param receiver The address of the receiver
/// @return The maximum amount of shares that can be issued
#[public]
#[view]
fn max_issue(receiver: AztecAddress) -> u128 { /* ... */ }
```

### preview_issue

```rust
/// @notice Simulates the effects of an issue at the current block
/// @param shares The amount of shares to issue
/// @return The amount of assets required to issue the shares
#[public]
#[view]
fn preview_issue(shares: u128) -> u128 { /* ... */ }
```

### max_withdraw

```rust
/// @notice Returns the maximum amount of the underlying asset that can be withdrawn from the owner's public balance
/// @dev This does NOT include private balance - private holders must track their own balance
/// @param owner The address of the owner
/// @return The maximum amount of assets that can be withdrawn
#[public]
#[view]
fn max_withdraw(owner: AztecAddress) -> u128 { /* ... */ }
```

### preview_withdraw

```rust
/// @notice Simulates the effects of a withdrawal at the current block
/// @param assets The amount of assets to withdraw
/// @return The amount of shares that would be burned
#[public]
#[view]
fn preview_withdraw(assets: u128) -> u128 { /* ... */ }
```

### max_redeem

```rust
/// @notice Returns the maximum amount of Vault shares that can be redeemed from the owner's public balance
/// @dev This does NOT include private balance - private holders must track their own balance
/// @param owner The address of the owner
/// @return The maximum amount of shares that can be redeemed
#[public]
#[view]
fn max_redeem(owner: AztecAddress) -> u128 { /* ... */ }
```

### preview_redeem

```rust
/// @notice Simulates the effects of a redemption at the current block
/// @param shares The amount of shares to redeem
/// @return The amount of assets that would be received
#[public]
#[view]
fn preview_redeem(shares: u128) -> u128 { /* ... */ }
```

### get_vault_offset

```rust
/// @notice Returns the vault offset
/// @return The offset value
#[public]
#[view]
fn get_vault_offset() -> u128 { /* ... */ }
```

## Deployment Guide

Deploying a Vault requires a two-step process because the vault and shares token are separate contracts with a circular dependency — the shares token needs the vault as its minter, and the vault needs to know the shares token address. To simplify this, the [`VaultDeployer`](../vault_deployer) contract wraps both steps into a single user-facing transaction: deploying a fresh `VaultDeployer` instance per vault atomically deploys and wires the vault + shares token pair.

A public factory that deploys and wires both contracts in one step is not currently possible because contract instance publishing (`publish_contract_instance_for_public_execution`) is private-only — it relies on a private oracle and `PrivateContext`. The `VaultDeployer` works around this by running the publishing + linking logic in its own private initializer, instead of as a reusable public factory. This approach can be revisited once [public instance registration](https://github.com/AztecProtocol/aztec-packages/issues/20771) is supported.

### Step 1: Publish the contract classes

The `Vault` and `Token` contract classes must be published on-chain once per network before any vault can be deployed. Each vault then references them by `ContractClassId`.

### Step 2: Deploy a `VaultDeployer` instance for the vault

Deploy a new `VaultDeployer` instance with one of its two initializers. The initializer derives the vault and shares addresses (with the deployer instance as their `deployer`), publishes both contract instances, enqueues their constructors, and finally enqueues `set_shares_token` (or `set_shares_token_with_initial_deposit`) on the vault — all within the same transaction. The deployer-of-instance check on the vault ensures only this `VaultDeployer` instance can perform the link.

#### Deployment without initial deposit

```rust
VaultDeployer::interface().deploy_vault(
    asset,
    vault_offset,
    vault_class_id,
    shares_name,
    shares_symbol,
    shares_decimals,
    shares_class_id,
)
```

When using this deployment method, the vault relies on a **virtual shares offset** mechanism to mitigate inflation (donation) attacks. The deployer specifies the `vault_offset` value during vault construction.

This offset introduces virtual assets and virtual shares into the exchange-rate calculation. By doing so, it **dampens exchange-rate manipulation and reduces rounding-based griefing**, which is a key enabler of inflation attacks in empty or near-empty ERC-4626 vaults.

Increasing the offset generally makes early-stage manipulation more expensive and reduces the attacker's ability to force victims into receiving zero or negligible shares. However, larger offsets also affect share pricing for small deposits and can introduce UX and accounting tradeoffs. As a result, **choosing an appropriate offset is a balance between security and precision**.

It is the **deployer's responsibility** to evaluate whether `offset = 1` provides sufficient protection for their specific use case, or if a larger value is needed. Factors to consider include:

- Expected minimum and typical deposit sizes
- Likelihood of front-running or MEV
- Whether the vault exposes methods where users supply both `assets` and `shares` (common for private flows where the exchange rate cannot be computed inside the private context)
- The overall risk profile and value secured by the vault

For a detailed analysis of virtual offsets as a mitigation strategy, see:
https://www.openzeppelin.com/news/a-novel-defense-against-erc4626-inflation-attacks

> **WARNING — Inflation Attack Risk**
>
> Empty or nearly-empty ERC-4626 vaults are vulnerable to **inflation attacks** (also known as donation attacks). An attacker can manipulate the share-to-asset exchange rate by front-running early deposits with a combination of a small deposit and a large donation. This can cause victims to receive zero or negligible shares for their deposit, effectively stranding their assets in the vault.
>
> This class of attack is most effective when total assets are low and deposits can be front-run. On Aztec, some private vault methods accept both `assets` and `shares` as inputs (because the exchange rate may not be computable inside the private context). If callers can choose these values freely (or if integrators don't enforce conservative bounds), manipulation and rounding issues can become easier to exploit.
>
> **An `offset = 1` provides baseline protection, but may not be sufficient in all scenarios — particularly when multiple deposits can be front-run or when very small deposits are expected.**

#### Deployment with initial deposit

For stronger protection, use the `deploy_vault_with_initial_deposit` initializer to seed the vault as part of the same transaction:

```rust
VaultDeployer::interface().deploy_vault_with_initial_deposit(
    asset,
    vault_offset,
    vault_class_id,
    shares_name,
    shares_symbol,
    shares_decimals,
    shares_class_id,
    initial_deposit,
    depositor,
    nonce,
)
```

The `depositor` can be any address that provides an authwit for the `initial_deposit` amount on the asset token. During setup:

1. The specified `initial_deposit` of assets is transferred from the `depositor` to the vault
2. Corresponding shares are minted to the vault contract address itself and are permanently locked
3. These shares act as **dead shares**

This approach is inspired by mitigation strategies used in production systems (e.g., Morpho-style vault seeding). By establishing a non-trivial initial asset and share base, early exchange-rate manipulation becomes economically impractical.

Rather than relying on virtual math alone, this method ensures that an attacker would need to commit **economically significant capital relative to the initial deposit and expected user deposits** in order to meaningfully influence the exchange rate.

> **NOTE — Setup Preparation**
>
> The initial deposit is executed internally via a `transfer_public_to_public` call on the underlying asset token. As a result:
>
> - The `depositor` **must hold the `initial_deposit` amount in their public balance**
> - An **authwit must be signed** authorizing this public transfer
> - The **vault contract address must be known in advance** in order to correctly compute and sign the authwit
>
> The vault address is fully determined by the `VaultDeployer` instance address (used as the `deployer`), the deployer's salt, the vault `ContractClassId`, and the vault's initialization hash (derived from the constructor selector and args). Deployers should precompute it from the `VaultDeployer` instantiation params and set up the depositor's public balance and authwit before submitting the `deploy_vault_with_initial_deposit` transaction.

**Choosing the Initial Deposit Amount:**

- The deposit should be large enough that the donation required to round the smallest expected user deposits down to zero is economically unfeasible or orders of magnitude larger than the expected attacker's profit.
- A common heuristic is to seed the vault with an amount comparable to, or larger than, early expected inflows. However, beware that asset's decimals play an important role here:
    - 18 decimals (e.g. DAI): if the smallest, economically significant user deposit is expected to be 1 DAI, an initial deposit of 1 DAI would mean that an attacker would need one quintillion DAIs (10^18 DAI) to exploit 1-DAI deposits. Even a smaller initial deposit would probably be enough.
    - 6 decimals (e.g USDC): an attacker would need in comparison only 1 million USDC to exploit 1-USDC deposits. It might still be a strong protection against donation attacks in some cases, but it does not make them unfeasible.
- Larger deposits provide stronger protection but represent permanently locked capital.

> **NOTE — Dead Shares Should Be Unrecoverable**
>
> Dead shares are intended to remain permanently locked and are not expected to be redeemed under normal operation.

### Combining Offset and Dead Shares

For maximum robustness, the virtual offset mechanism can be combined with an initial deposit:

- The **offset** provides baseline protection against rounding-based manipulation
- The **initial deposit** establishes meaningful initial liquidity, making economic attacks impractical

This layered approach is recommended for deployments where the vault is expected to accept deposits immediately after deployment and/or secure significant value.
