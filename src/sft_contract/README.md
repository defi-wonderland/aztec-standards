# SFT Contract

The `SFT` contract implements an ERC-1155-like semi-fungible token with Aztec-specific privacy extensions. It supports transfers and interactions through both private and public balances for multiple token types, offering full coverage of Aztec's confidentiality features for multi-token applications.

This implementation provides a robust foundation for semi-fungible tokens on Aztec, enabling developers to build applications with flexible privacy controls and seamless interoperability between private and public states across multiple token types within a single contract.

## Storage Fields

- `name: FieldCompressedString`: SFT collection name (compressed).
- `symbol: FieldCompressedString`: SFT collection symbol (compressed).
- `private_sfts: Map<AztecAddress, PrivateSet<SFTNote>>`: Private SFT balances per account.
- `public_sfts: Map<(AztecAddress, Field), u128>`: Public balances per account and token ID.
- `total_supply: Map<Field, u128>`: Total supply per token ID.
- `public_token_type_exists: Map<Field, bool>`: Token type existence mapping.
- `minter: AztecAddress`: Authorized minter address.
- `upgrade_authority: AztecAddress`: Address allowed to perform contract upgrades (zero address if not upgradeable).

## Initializer Functions

### constructor_with_minter
```rust
/// @notice Initializes the SFT contract with a minter
/// @param name The name of the SFT collection
/// @param symbol The symbol of the SFT collection
/// @param minter The address of the minter
/// @param upgrade_authority The address of the upgrade authority (zero if not upgradeable)
#[public]
#[initializer]
fn constructor_with_minter(
    name: str<31>,
    symbol: str<31>,
    minter: AztecAddress,
    upgrade_authority: AztecAddress,
) { /* ... */ }
```

## View Functions

### balance_of_public_by_token_id
```rust
/// @notice Returns the public balance of `owner` for `token_id`
/// @param owner The address of the owner
/// @param token_id The ID of the token type
/// @return The public balance of `owner` for `token_id`
#[public]
#[view]
fn balance_of_public_by_token_id(owner: AztecAddress, token_id: Field) -> u128 { /* ... */ }
```

### total_supply
```rust
/// @notice Returns the total supply of `token_id`
/// @param token_id The ID of the token type
/// @return The total supply of `token_id`
#[public]
#[view]
fn total_supply(token_id: Field) -> u128 { /* ... */ }
```

### public_get_name
```rust
/// @notice Returns the name of the SFT collection
/// @return The name of the SFT collection
#[public]
#[view]
fn public_get_name() -> FieldCompressedString { /* ... */ }
```

### public_get_symbol
```rust
/// @notice Returns the symbol of the SFT collection
/// @return The symbol of the SFT collection
#[public]
#[view]
fn public_get_symbol() -> FieldCompressedString { /* ... */ }
```

### public_token_type_exists
```rust
/// @notice Returns whether a token type exists
/// @param token_id The ID of the token type
/// @return Whether the token type exists
#[public]
#[view]
fn public_token_type_exists(token_id: Field) -> bool { /* ... */ }
```

## Utility Functions

### balance_of_private_by_token_id
```rust
/// @notice Returns the private balance of `owner` for `token_id`
/// @param owner The address of the owner
/// @param token_id The ID of the token type
/// @param nonce The nonce used for authwit
/// @return The private balance of `owner` for `token_id`
#[utility]
unconstrained fn balance_of_private_by_token_id(
    owner: AztecAddress,
    token_id: Field,
    nonce: Field,
) -> u128 { /* ... */ }
```

## Public Functions

### create_token_type
```rust
/// @notice Creates a new token type
/// @dev Only callable by the minter
/// @param token_id The ID of the new token type
#[public]
fn create_token_type(token_id: Field) { /* ... */ }
```

### transfer_public_to_public
```rust
/// @notice Transfers SFTs from public balance to public balance
/// @dev Public call to decrease account balance and a public call to increase recipient balance
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The ID of the token type
/// @param nonce The nonce used for authwit
#[public]
fn transfer_public_to_public(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    nonce: Field,
) { /* ... */ }
```

### transfer_public_to_commitment
```rust
/// @notice Finalizes a transfer of SFT from public balance of `from` to a commitment of `to`
/// @dev The transfer must be prepared by calling `initialize_transfer_commitment` first and the resulting
/// `commitment` must be passed as an argument to this function
/// @param from The address of the sender
/// @param token_id The ID of the token type
/// @param commitment The Field representing the commitment (privacy entrance)
/// @param nonce The nonce used for authwit
#[public]
fn transfer_public_to_commitment(
    from: AztecAddress,
    token_id: Field,
    commitment: Field,
    nonce: Field,
) { /* ... */ }
```

### mint_to_public
```rust
/// @notice Mints SFTs to a public balance
/// @dev Increases the public balance of `to` by 1 for `token_id` and the total supply
/// @param to The address of the recipient
/// @param token_id The ID of the token type
#[public]
fn mint_to_public(
    to: AztecAddress,
    token_id: Field,
) { /* ... */ }
```

### burn_public
```rust
/// @notice Burns SFTs from a public balance
/// @dev Burns SFTs from a public balance and updates the total supply
/// @param from The address of the sender
/// @param token_id The ID of the token type
/// @param nonce The nonce used for authwit
#[public]
fn burn_public(
    from: AztecAddress,
    token_id: Field,
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
/// @notice Transfer SFTs from private balance to public balance
/// @dev Spends notes, emits a new note (SFTNote) with any remaining change, and enqueues a public call
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The ID of the token type
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_public(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    nonce: Field,
) { /* ... */ }
```

### transfer_private_to_public_with_commitment
```rust
/// @notice Transfer SFTs from private balance to public balance with a commitment
/// @dev Spends notes, emits a new note (SFTNote) with any remaining change, enqueues a public call, and returns a partial note
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The ID of the token type
/// @param nonce The nonce used for authwit
/// @return commitment The partial note utilized for the transfer commitment (privacy entrance)
#[private]
fn transfer_private_to_public_with_commitment(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    nonce: Field,
) -> Field { /* ... */ }
```

### transfer_private_to_private
```rust
/// @notice Transfer SFTs from private balance to private balance
/// @dev Spends notes, emits a new note (SFTNote) with any remaining change, and sends a note to the recipient
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The ID of the token type
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_private(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    nonce: Field,
) { /* ... */ }
```

### transfer_private_to_commitment
```rust
/// @notice Transfer SFTs from private balance to the recipient commitment (recipient must create a commitment first)
/// @dev Spends notes, emits a new note (SFTNote) with any remaining change, and enqueues a public call
/// @param from The address of the sender
/// @param token_id The ID of the token type
/// @param commitment The Field representing the commitment (privacy entrance that the recipient shares with the sender)
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_commitment(
    from: AztecAddress,
    token_id: Field,
    commitment: Field,
    nonce: Field,
) { /* ... */ }
```

### transfer_public_to_private
```rust
/// @notice Transfer SFTs from public balance to private balance
/// @dev Enqueues a public call to decrease account balance and emits a new note with balance difference
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The ID of the token type
/// @param nonce The nonce used for authwit
#[private]
fn transfer_public_to_private(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    nonce: Field,
) { /* ... */ }
```

### initialize_transfer_commitment
```rust
/// @notice Initializes a transfer commitment to be used for transfers/mints
/// @dev Returns a partial note that can be used to execute transfers/mints
/// @param token_id The ID of the token type
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param completer The address of the completer
/// @return commitment The partial note initialized for the transfer/mint commitment
#[private]
fn initialize_transfer_commitment(
    token_id: Field,
    from: AztecAddress,
    to: AztecAddress,
    completer: AztecAddress,
) -> Field { /* ... */ }
```

### mint_to_private
```rust
/// @notice Mints SFTs into a private balance
/// @dev Requires minter, enqueues supply update
/// @param to The address of the recipient
/// @param token_id The ID of the token type
#[private]
fn mint_to_private(to: AztecAddress, token_id: Field) { /* ... */ }
```

### burn_private
```rust
/// @notice Burns SFTs from a private balance
/// @dev Requires authwit, enqueues supply update
/// @param from The address of the sender
/// @param token_id The ID of the token type
/// @param nonce The nonce used for authwit
#[private]
fn burn_private(from: AztecAddress, token_id: Field, nonce: Field) { /* ... */ }
```

## SFT Note Structure

The `SFTNote` is the core data structure for private SFT balances:

```rust
struct SFTNote {
    owner: AztecAddress,    // Owner of the SFT
    token_id: Field,        // Token type identifier
    header: NoteHeader,     // Standard note header
}
```

Key features:
- Each note represents ownership of one SFT of a specific token type
- Multiple notes can exist for the same owner and token type
- Notes are nullified when spent and new notes are created for transfers
- Supports partial spending with change notes for multi-token operations
