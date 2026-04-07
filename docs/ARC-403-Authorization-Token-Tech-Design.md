# ARC-403: Authorization Token — Tech Design

> Aztec Request for Comment 403, aka AuthToken, an extension of the ARC-20 Token, named after the HTTP 403 Forbidden status code.

## Summary

ARC-403 adds an optional authorization hook to the ARC-20 token standard. When configured, every balance-changing operation (transfer, mint, burn) calls an external **authorization contract** that can enforce arbitrary compliance policies — KYC checks, transfer allowances, sanctions screening, information logging, etc.

The design is intentionally minimal: the token contract itself does not implement any policy logic. It only knows *whether* an authorization contract is set and, if so, delegates a `(from, amount)` call to it. If the authorization contract reverts, the token operation reverts. If no authorization contract is set, the hook is a no-op and the token behaves as a standard ARC-20.

This approach preserves full ARC-20 interface compatibility — applications (AMMs, bridges, wallets) interact with ARC-403 tokens identically to vanilla tokens.

## Motivation

Aztec's privacy-by-design architecture means that new account contracts remain invisible to observers and transaction details are confidential. While this fulfills the platform's core mission, many token issuers require conditional privacy — ensuring that transaction confidentiality privileges extend exclusively to validated participants (KYC-verified users, permissible jurisdictions, etc.).

ARC-403 allows compliance requirements to coexist with privacy by providing a standardized hook interface that authorization contracts implement.

## Architecture

### Token-Side Integration

The only storage addition to the ARC-20 token is a single immutable field:

```rust
auth_contract: PublicImmutable<AztecAddress, Context>
```

Set during construction via either `constructor_with_initial_supply` or `constructor_with_minter`, both of which accept an `auth_contract: AztecAddress` parameter. A zero address disables the hook. A public view function `get_auth_contract()` is provided to query the configured address.

Two internal functions handle the hook dispatch:

```rust
#[internal("public")]
fn _call_auth_public(from: AztecAddress, amount: u128) {
    let auth = self.storage.auth_contract.read();
    if !auth.eq(AztecAddress::zero()) {
        self.call(AuthorizationContract::at(auth).authorize_public(from, amount));
    }
}

#[internal("private")]
fn _call_auth_private(from: AztecAddress, amount: u128) {
    let auth = self.storage.auth_contract.read();
    if !auth.eq(AztecAddress::zero()) {
        AuthorizationContract::at(auth).authorize_private(from, amount).call(self.context);
    }
}
```

Token functions that execute in a private context call `_call_auth_private`, while functions that execute in a public context call `_call_auth_public`.

### Hook Dispatch Table

| Token function | Context | Hook called | `from` value |
|---|---|---|---|
| `transfer_private_to_private` | private | `authorize_private` | `from` |
| `transfer_private_to_public` | private | `authorize_private` | `from` |
| `transfer_private_to_public_with_commitment` | private | `authorize_private` | `from` |
| `transfer_private_to_commitment` | private | `authorize_private` | `from` |
| `transfer_public_to_private` | private | `authorize_private` | `from` |
| `transfer_public_to_public` | public | `authorize_public` | `from` |
| `transfer_public_to_commitment` | public | `authorize_public` | `from` |
| `mint_to_private` | private | `authorize_private` | `AztecAddress::zero()` |
| `mint_to_public` | public | `authorize_public` | `AztecAddress::zero()` |
| `mint_to_commitment` | public | `authorize_public` | `AztecAddress::zero()` |
| `burn_private` | private | `authorize_private` | `from` |
| `burn_public` | public | `authorize_public` | `from` |

For mints, `from` is `AztecAddress::zero()`, signaling that the operation is a mint rather than a transfer/burn. Burn operations are indistinguishable from transfers, because the hook does not take the `to` parameter as input.

### Authorization Contract Interface

The authorization contract must implement two external functions:

```rust
#[aztec]
contract AuthorizationContract {
    /// @notice Private authorization hook — called by the token in private context
    /// @param from The address tokens are moved from (zero for mints)
    /// @param amount The amount of tokens being moved
    #[external("private")]
    fn authorize_private(from: AztecAddress, amount: u128);

    /// @notice Public authorization hook — called by the token in public context
    /// @param from The address tokens are moved from (zero for mints)
    /// @param amount The amount of tokens being moved
    #[external("public")]
    fn authorize_public(from: AztecAddress, amount: u128);
}
```

Inside these functions, the authorization contract has access to:

| Available data | How to access |
|---|---|
| The token being transferred | `context.msg_sender()` (the token contract is the caller) |
| The account spending tokens | `from` parameter |
| The transfer amount | `amount` parameter |
| Arbitrary private data (proofs, signatures) | `unsafe { capsules::load(...) }` (private context only) |

**Notably absent from the interface:** `to` (recipient), `sender` (the original `msg_sender` of the token function, e.g. an AMM), and `nonce`. See Design Decisions for the rationale.

## Test Coverage

A no-op authorization contract (both hooks are empty, allowing all operations) is included at `src/test/test_authorization_contract/` for testing purposes. The test suite (`src/test/authorization.nr`) deploys it alongside the token to verify that the hook machinery is wired correctly without restricting any flow.

## Design Decisions

### Omit `sender` from the hook interface

The `msg_sender` of the token function (e.g. an AMM contract) is not included in the hook interface. Community feedback concluded that:

- No practical policy can leverage "who the requestor is" since the requestor identity can be circumvented by routing the call through another operator contract.
- It adds complexity without clear benefit.

### Omit `to` from the hook interface

The `to` (recipient) parameter was not included because it cannot be provided consistently across all transfer flows:

1. **Commitment-based transfers** (`transfer_*_to_commitment`, `mint_to_commitment`): The recipient is sealed inside a hash preimage that the sender never has. Passing a sentinel value creates a false promise of recipient enforcement.
2. **A commitment-creation hook does not fix this**: While `initialize_transfer_commitment` runs in private and knows the real `to`, the amount is unknown at creation time.
3. **No-setup partial notes will make it worse**: Future Aztec versions will support commitments created entirely off-chain (no on-chain `initialize_transfer_commitment` call), meaning there will be no transaction to hook into for recipient validation at all.
4. **The fundamental issue**: A hook that *appears* to screen recipients but silently passes all commitment-based transfers is more dangerous than one that makes no claim about recipients at all.

**Consequence**: A blocked-list address can still *receive* funds (since `to` is not checked), but depending on the policy, would never be able to *spend* them (since `from` is checked on every outgoing operation).

### Not including `nonce`

The `nonce` used in authwit disambiguation is not forwarded to the authorization contract. The rationale is that higher-level contracts (e.g., AMMs) may use `nonce` for their own security mechanisms, and forwarding it to the authorization contract could interfere with those uses. If extra data is needed for authorization (e.g., a ZK proof), it should be loaded via capsules inside the authorization contract itself.

## Authorization Contract Implementation Examples

These are illustrative examples of what policies could live inside authorization contracts. They are not part of the ARC-403 standard itself, so some will be implemented on a separate repo to showcase how the standard should be used.

### Allowlist

The authorization contract maintains a set of approved addresses. On each transfer, it checks that `from` is in the set.

- **Private variant**: The user provides a Merkle inclusion proof via capsules. The authorization contract verifies the proof against a known root.
- **Public variant**: The authorization contract reads a public mapping to check whether `from` is approved.

### Blocklist

The authorization contract maintains a set of blocked addresses publicly. On each transfer, it checks that `from` is not in a set.

### Transfer Accumulator (Volume Caps)

An entity performs KYC on users and issues an allowance note `H(user, allowance, nonce)`. On each transfer:

1. The user nullifies the current allowance note.
2. A new note is created with `allowance - amount` and `nonce + 1`.
3. The circuit enforces that no duplicate nonce exists and that the allowance hasn't underflowed.

This allows the entity to control *how much* a user can transfer without knowing *what* they transferred.

### Information Leaking (Audit Trail)

The authorization contract does not restrict transfers but emits an encrypted log to the token issuer for each operation. This provides an audit trail that can be shared with authorities on request, without affecting the user's ability to transact.

### Signature by Authority

The issuer runs an off-chain approval channel. Before transferring, the user requests a signed authorization. The authorization contract verifies the signature in-circuit via capsules. This gives the issuer real-time control over which transfers proceed.

### ZK Identity Proofs (e.g., ZkPassport)

The authorization contract enforces that users provide a zero-knowledge proof of identity attributes (age > 18, nationality, etc.) via capsules.

---

## Questions

1. Should the hook receive the selector of the token function called as parameter for better granularity?
2. ~~Should we distinguish burns from transfers?~~ Burn and transfer operations look identical from the authorization contract point of view.
   - ~~Should the hook receive an operation type enum (e.g., `Mint`, `Transfer`, `Burn`) so that policies can differentiate?~~
3. ~~**Should the recipient address `to` be included in the hook interface?**~~ (See Design Decisions above for resolution)
