# NFT Contract

The `NFT` contract implements an ERC-721-like non-fungible token with Aztec-specific privacy extensions. It supports transfers and interactions through both private and public ownership, offering full coverage of Aztec's confidentiality features for unique digital assets.

This contract provides a comprehensive NFT implementation that allows seamless transitions between private and public ownership states, making it ideal for applications requiring flexible privacy controls.

## Storage Fields

- `name: FieldCompressedString`: NFT collection name (compressed).
- `symbol: FieldCompressedString`: NFT collection symbol (compressed).
- `private_nfts: Map<AztecAddress, PrivateSet<NFTNote>>`: Private NFT ownership per account.
- `nft_exists: Map<Field, bool>`: Mapping from token ID to existence status.
- `public_owners: Map<Field, AztecAddress>`: Public ownership mapping from token ID to owner address.
- `minter: AztecAddress`: Authorized minter address.
- `upgrade_authority: AztecAddress`: Address allowed to perform contract upgrades (zero address if not upgradeable).

## Initializer Functions

### constructor_with_minter
```rust
/// @notice Initializes the NFT contract with a minter
/// @param name The name of the NFT collection
/// @param symbol The symbol of the NFT collection
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

## Private Functions

### transfer_private_to_public
```rust
/// @notice Transfers token by id from private owner to a public owner
/// @dev Removes token from private owner, and enqueues a public call to update the public owner
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The id of the token to transfer
/// @param _nonce The nonce used for authwit
#[private]
fn transfer_private_to_public(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    _nonce: Field,
) { /* ... */ }
```

### transfer_private_to_public_with_commitment
```rust
/// @notice Transfers token by id from private owner to a public owner with a commitment
/// @dev Removes token from private owner, enqueues a public call to update the public owner, and returns a commitment
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The id of the token to transfer
/// @param _nonce The nonce used for authwit
/// @return commitment The partial nft note utilized for the transfer commitment (privacy entrance)
#[private]
fn transfer_private_to_public_with_commitment(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    _nonce: Field,
) -> Field { /* ... */ }
```

### transfer_private_to_private
```rust
/// @notice Transfers token by id from private owner to another private owner
/// @dev Removes token by id from private owner, and sends a nft note with id to the recipient
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The id of the token to transfer
/// @param _nonce The nonce used for authwit
#[private]
fn transfer_private_to_private(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    _nonce: Field,
) { /* ... */ }
```

### transfer_private_to_commitment
```rust
/// @notice Transfers token by id from private owner to the recipient commitment (recipient must create a commitment first)
/// @dev Removes token by id from private owner, and enqueues a public call to complete the commitment
/// @param from The address of the sender
/// @param token_id The id of the token to transfer
/// @param commitment The commitment to use for the transfer
/// @param _nonce The nonce used for authwit
#[private]
fn transfer_private_to_commitment(
    from: AztecAddress,
    token_id: Field,
    commitment: Field,
    _nonce: Field,
) { /* ... */ }
```

### transfer_public_to_private
```rust
/// @notice Transfers token by id from public owner to private owner
/// @dev Enqueues a public call to remove the public owner, and emits a nft note with id to the recipient
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The id of the token to transfer
/// @param _nonce The nonce used for authwit
#[private]
fn transfer_public_to_private(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    _nonce: Field,
) { /* ... */ }
```

### initialize_transfer_commitment
```rust
/// @notice Initializes a transfer commitment to be used for transfers
/// @dev Returns a partial nft note that can be used to execute transfers
/// @param from The address of the sender
/// @param to The address of the recipient
/// @return commitment The partial nft note utilized for the transfer commitment (privacy entrance)
#[private]
fn initialize_transfer_commitment(from: AztecAddress, to: AztecAddress) -> Field { /* ... */ }
```

### mint_to_private
```rust
/// @notice Mints a token to a private address
/// @dev Asserts that the caller is an authorized minter
/// @param to The address of the recipient
/// @param token_id The id of the token to mint
#[private]
fn mint_to_private(to: AztecAddress, token_id: Field) { /* ... */ }
```

### burn_private
```rust
/// @notice Burns a token from a private address
/// @dev Asserts that the caller is token owner, removes private token owner, and enqueues a public call to burn token
/// @param from The address of the owner
/// @param token_id The id of the token to burn
/// @param _nonce The nonce used for authwit
#[private]
fn burn_private(from: AztecAddress, token_id: Field, _nonce: Field) { /* ... */ }
```

## Public Functions

### transfer_public_to_public
```rust
/// @notice Transfers a token from one public owner to another public owner
/// @dev Public call that asserts that the caller is the token owner, and updates the public owner
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The id of the token to transfer
/// @param _nonce The nonce used for authwit
#[public]
fn transfer_public_to_public(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    _nonce: Field,
) { /* ... */ }
```

### transfer_public_to_commitment
```rust
/// @notice Transfers a token to a commitment
/// @dev Public call that asserts that the caller is the token owner, and updates the public owner, and completes the commitment
/// @param from The address of the sender
/// @param token_id The id of the token to transfer
/// @param commitment The commitment to use for the transfer
/// @param _nonce The nonce used for authwit
#[public]
fn transfer_public_to_commitment(
    from: AztecAddress,
    token_id: Field,
    commitment: Field,
    _nonce: Field,
) { /* ... */ }
```

### mint_to_public
```rust
/// @notice Mints a token to a public address
/// @dev Asserts that the caller is an authorized minter
/// @param to The address of the recipient
/// @param token_id The id of the token to mint
#[public]
fn mint_to_public(to: AztecAddress, token_id: Field) { /* ... */ }
```

### burn_public
```rust
/// @notice Burns a token from a public address
/// @dev Asserts that token exists and that the caller is token owner, removes public token owner, and burns token
/// @param from The address of the owner
/// @param token_id The id of the token to burn
/// @param _nonce The nonce used for authwit
#[public]
fn burn_public(from: AztecAddress, token_id: Field, _nonce: Field) { /* ... */ }
```

### upgrade_contract
```rust
/// @notice Upgrades the contract to a new contract class id
/// @dev The upgrade authority must be set and the upgrade will only be effective after the upgrade delay has passed
/// @param new_contract_class_id The new contract class id
#[public]
fn upgrade_contract(new_contract_class_id: Field) { /* ... */ }
```

## View Functions

### public_get_name
```rust
/// @notice Returns the name of the NFT collection
/// @return name The name of the NFT collection
#[public]
#[view]
fn public_get_name() -> FieldCompressedString { /* ... */ }
```

### public_get_symbol
```rust
/// @notice Returns the symbol of the NFT collection
/// @return symbol The symbol of the NFT collection
#[public]
#[view]
fn public_get_symbol() -> FieldCompressedString { /* ... */ }
```

### public_owner_of
```rust
/// @notice Returns the owner of a token by id
/// @param token_id The id of the token
/// @return owner The owner of the token
#[public]
#[view]
fn public_owner_of(token_id: Field) -> AztecAddress { /* ... */ }
```

## Utility Functions

### get_private_nfts
```rust
/// @notice Returns an array of token IDs owned by `owner` in private and a flag indicating whether a page limit was reached
/// @dev Starts getting the notes from page with index `page_index`
/// @dev Zero values in the array are placeholder values for non-existing notes
/// @param owner The address of the owner
/// @param page_index The index of the page to start getting notes from
/// @return owned_nft_ids An array of token IDs owned by `owner`
/// @return page_limit_reached A flag indicating whether a page limit was reached
#[utility]
unconstrained fn get_private_nfts(
    owner: AztecAddress,
    page_index: u32,
) -> ([Field; MAX_NOTES_PER_PAGE], bool) { /* ... */ }
```

