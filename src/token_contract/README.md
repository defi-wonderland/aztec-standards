# Token Contract

The `Token` contract implements an ERC-20-like token with Aztec-specific privacy extensions. It supports transfers and interactions through both private and public balances, offering full coverage of Aztec's confidentiality features.

This implementation provides a robust foundation for fungible tokens on Aztec, enabling developers to build applications with flexible privacy controls and seamless interoperability between private and public states.

## AIP-20: Aztec Token Standard

This contract follows the [AIP-20 Aztec Token Standard](https://forum.aztec.network/t/request-for-comments-aip-20-aztec-token-standard/7737). Feel free to review and discuss the specification on the Aztec forum.

## ARC-403: Authorization Hook

This contract also implements ARC-403, an optional authorization hook that calls an external **authorization contract** on every transfer and burn. This enables compliance policies (KYC, allowlists, transfer caps, sanctions screening, audit logging, pausability, etc.) to be plugged in without changing the token interface. If no authorization contract is set, the token behaves as a standard ARC-20. See [ARC-403 Authorization Hook](#arc-403-authorization-hook-1) for details.

## Transfer Events

The contract emits a public `Transfer { from, to, amount }` event on every balance-changing operation (mints, burns, public transfers, and cross-domain private ↔ public moves), enabling indexers to track token movements.

| Operation | Event Pattern |
|-----------|---------------|
| Mint to public | `Transfer(0x0, recipient, amount)` |
| Mint to private | `Transfer(0x0, PRIVATE_ADDRESS, amount)` |
| Burn from public | `Transfer(from, 0x0, amount)` |
| Burn from private | `Transfer(PRIVATE_ADDRESS, 0x0, amount)` |
| Public-to-public | `Transfer(from, to, amount)` |
| Public-to-private | `Transfer(from, PRIVATE_ADDRESS, amount)` |
| Private-to-public | `Transfer(PRIVATE_ADDRESS, to, amount)` |
| Private-to-private | _(no public events)_ |

**Sentinel values:** `0x0` denotes mint origin (`from`) or burn destination (`to`), following ERC-20. `PRIVATE_ADDRESS` (sha224 of `"PRIVATE_ADDRESS"`) denotes the private side of a balance change when the counterpart cannot be revealed.
## Storage Fields

- `name: str<31>`: Token name (compressed).
- `symbol: str<31>`: Token symbol (compressed).
- `decimals: u8`: Decimal precision.
- `private_balances: Map<AztecAddress, BalanceSet>`: Private balances per account.
- `public_balances: Map<AztecAddress, u128>`: Public balances per account.
- `total_supply: u128`: Total token supply.
- `minter: AztecAddress`: Authorized minter address (if set).
- `auth_contract: AztecAddress`: ARC-403 authorization contract address (zero address disables the hook).

## Initializer Functions

### constructor_with_initial_supply
```rust
/// @notice Initializes the token with an initial supply
/// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
/// @param name The name of the token
/// @param symbol The symbol of the token
/// @param decimals The number of decimals of the token
/// @param initial_supply The initial supply of the token
/// @param to The address to mint the initial supply to
/// @param auth_contract The ARC-403 authorization contract address (zero address to disable)
#[public]
#[initializer]
fn constructor_with_initial_supply(
    name: str<31>,
    symbol: str<31>,
    decimals: u8,
    initial_supply: u128,
    to: AztecAddress,
    auth_contract: AztecAddress,
) { /* ... */ }
```

### constructor_with_minter
```rust
/// @notice Initializes the token with a minter
/// @param name The name of the token
/// @param symbol The symbol of the token
/// @param decimals The number of decimals of the token
/// @param minter The address of the minter
/// @param auth_contract The ARC-403 authorization contract address (zero address to disable)
#[public]
#[initializer]
fn constructor_with_minter(
    name: str<31>,
    symbol: str<31>,
    decimals: u8,
    minter: AztecAddress,
    auth_contract: AztecAddress,
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

### get_auth_contract
```rust
/// @notice Returns the ARC-403 authorization hook contract address
/// @return The auth contract address (zero address means authorization is disabled)
#[public]
#[view]
fn get_auth_contract() -> AztecAddress { /* ... */ }
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

## ARC-403 Authorization Hook

The authorization contract address is set at construction via the `auth_contract` parameter on both constructors and stored as an immutable field. A zero address disables the hook. When set, each hooked function calls either `authorize_private(from, amount, selector)` or `authorize_public(from, amount, selector)` on the authorization contract after authwit validation and before any balance mutation. The token operation reverts if the authorization call reverts. The hook variant matches the calling function's context — private functions call `authorize_private`, public functions call `authorize_public` — and the `selector` passed is the calling function's own selector.

| Token function | Hook called |
|----------------|-------------|
| `transfer_private_to_private` | `authorize_private` |
| `transfer_private_to_public` | `authorize_private` |
| `transfer_private_to_public_with_commitment` | `authorize_private` |
| `transfer_private_to_commitment` | `authorize_private` |
| `transfer_public_to_private` | `authorize_private` |
| `transfer_public_to_public` | `authorize_public` |
| `transfer_public_to_commitment` | `authorize_public` |
| `burn_private` | `authorize_private` |
| `burn_public` | `authorize_public` |

### Considerations

- **Mints are not hooked.** `mint_to_public`, `mint_to_private`, and `mint_to_commitment` do not call the hook — minting is already gated by the `minter` address set at construction.
- **`to` is not forwarded to the hook.** The recipient cannot be provided consistently across all transfer flows (commitment-based transfers seal the recipient inside a hash preimage the sender never sees), so it is omitted entirely rather than passed inconsistently. As a result, a blocked sender can still receive funds, but might not be able to spend them.
- **`transfer_public_to_private` is not fully private.** It calls `authorize_private`, but spending a public balance inherently reveals `from` and `amount` on-chain regardless of any privacy the authorization contract provides. Authorization contracts can use the `selector` argument to distinguish this case.

Reference implementations of authorization contracts (allowlist, signature-by-authority, transfer accumulator, pausable, etc.) can be found in the [aztec-arc403-extensions](https://github.com/defi-wonderland/aztec-arc403-extensions) repository.