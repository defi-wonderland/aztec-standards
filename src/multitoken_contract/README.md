# MultiToken Contract

The `MultiToken` contract implements an ERC-1155-like multi-token with Aztec-specific privacy extensions. A single contract holds many fungible token ids, each with its own independent balance, and every balance can live in either a private or a public domain with seamless moves between the two.

Compared to the single-asset [`Token`](../token_contract/README.md), every balance-changing function takes an extra `id: Field` selecting the token, there is no `decimals` and no `total_supply`, and the on-chain event is `TransferSingle` (ERC-1155 naming) instead of `Transfer`.

## ARC-403: Authorization Hook

Like `Token`, this contract implements the optional ARC-403 authorization hook: when an `auth_contract` is configured, every transfer and burn calls it before mutating balances, and the operation reverts if the hook reverts. If `auth_contract` is the zero address, the hook is disabled and the token behaves as a plain multi-token. The interface is **id-bearing** — the hook receives the token id so policies can differ per id:

- `authorize_private(from, id, amount, selector)` — called by private-context functions.
- `authorize_public(from, id, amount, selector)` — called by public-context functions.

| Function | Hook called |
|----------|-------------|
| `transfer_private_to_private` | `authorize_private` |
| `transfer_private_to_public` | `authorize_private` |
| `transfer_private_to_commitment` | `authorize_private` |
| `transfer_public_to_private` | `authorize_private` |
| `transfer_public_to_public` | `authorize_public` |
| `transfer_public_to_commitment` | `authorize_public` |
| `burn_private` | `authorize_private` |
| `burn_public` | `authorize_public` |

Mints (`mint_to_private`, `mint_to_public`, `mint_to_commitment`) are **not** hooked — minting is already gated by the `minter` address set at construction.

## TransferSingle Events

A public `TransferSingle { from, to, id, amount }` event is emitted only on operations whose token id is already revealed on-chain (any public-balance write or public commitment completion). Fully-private operations emit nothing, since an id-bearing event would leak the token id.

| Operation | Event Pattern |
|-----------|---------------|
| Mint to public | `TransferSingle(0x0, recipient, id, amount)` |
| Mint to commitment | `TransferSingle(0x0, PRIVATE_ADDRESS, id, amount)` |
| Burn from public | `TransferSingle(from, 0x0, id, amount)` |
| Public-to-public | `TransferSingle(from, to, id, amount)` |
| Public-to-commitment | `TransferSingle(from, PRIVATE_ADDRESS, id, amount)` |
| Public-to-private | `TransferSingle(from, PRIVATE_ADDRESS, id, amount)` |
| Private-to-public | `TransferSingle(PRIVATE_ADDRESS, to, id, amount)` |
| Mint to private / Burn from private | _(no public events)_ |
| Private-to-private / Private-to-commitment | _(no public events)_ |

**Sentinel values:** `0x0` denotes mint origin (`from`) or burn destination (`to`), following ERC-1155. `PRIVATE_ADDRESS` (sha224 of `"PRIVATE_ADDRESS"`) denotes the private side of a balance change when the counterpart cannot be revealed.

## Storage Fields

- `name: FieldCompressedString`: Token collection name (compressed).
- `symbol: FieldCompressedString`: Token collection symbol (compressed).
- `private_balances: Owned<MultiBalanceSet>`: A single private note set. Each `MultiTokenNote` self-describes its token id; per-owner scoping is `private_balances.at(owner)`, and per-id operations select notes where `token_id == id`.
- `public_balances: Map<Field, Map<AztecAddress, u128>>`: Public balances keyed by token id, then owner.
- `minter: AztecAddress`: Account permitted to mint any token id.
- `auth_contract: AztecAddress`: ARC-403 authorization contract address (zero address disables the hook).

## Function Reference

All addresses are `AztecAddress`; `id` is a `Field`, `amount` is a `u128`, and `nonce` (used for authwit) is a `Field`.

### Initializer

- `constructor_with_minter(name: FieldCompressedString, symbol: FieldCompressedString, minter, auth_contract)` — Initializes the multi-token with a minter and an optional ARC-403 auth contract.

### Private Functions

- `transfer_private_to_private(from, to, id, amount, nonce)` — Moves `amount` of `id` between private balances. Fully private (no event, no public effect).
- `transfer_private_to_public(from, to, id, amount, nonce)` — Spends private notes and enqueues a public credit to `to`.
- `transfer_private_to_commitment(from, id, commitment, amount, nonce)` — Spends private notes and completes an already-initialized commitment with `(id, amount)`.
- `transfer_public_to_private(from, to, id, amount, nonce)` — Enqueues a public debit of `from` and emits a private note to `to`.
- `initialize_transfer_commitment(to, completer) -> Field` — Creates a partial note (privacy entrance) to be completed by later transfers/mints. Id-agnostic: the completer binds `id` and `amount`.
- `mint_to_private(to, id, amount)` — Minter mints `id` into a private balance. Fully private.
- `burn_private(from, id, amount, nonce)` — Burns `id` from a private balance. Fully private.

### Public Functions

- `transfer_public_to_public(from, to, id, amount, nonce)` — Moves `amount` of `id` between public balances.
- `transfer_public_to_commitment(from, id, commitment, amount, nonce)` — Debits `from`'s public balance and completes a commitment prepared by `initialize_transfer_commitment`.
- `mint_to_public(to, id, amount)` — Minter mints `id` into a public balance.
- `mint_to_commitment(id, commitment, amount)` — Minter finalizes a mint into a commitment.
- `burn_public(from, id, amount, nonce)` — Burns `id` from a public balance.

### View Functions

- `balance_of_public(owner, id) -> u128` — Public balance of `owner` for `id`.
- `name() -> FieldCompressedString` — Token collection name.
- `symbol() -> FieldCompressedString` — Token collection symbol.
- `get_minter() -> AztecAddress` — Authorized minter address.
- `get_auth_contract() -> AztecAddress` — ARC-403 auth contract address (zero if disabled).

### Utility Functions

- `balance_of_private(owner, id) -> u128` — Off-chain helper that pages through the owner's notes filtered by `id` and sums their values. No on-chain or proving cost, and no fixed cap.
