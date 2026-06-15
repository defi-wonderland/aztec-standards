# Cyclic Deployer Contract

The `CyclicDeployer` atomically deploys and wires **two cyclically-dependent contracts** in a single transaction, working around the two-step initialization such a pair would otherwise require. The canonical example in this repository is the [`Vault`](../vault_contract) and its AIP-20 shares [`Token`](../token_contract) (see the vault [Deployment Guide](../vault_contract/README.md#deployment-guide)), and that pair is used as the worked example throughout — but the contract is type-agnostic and imports none of the contracts it deploys.

## The deploy-time cycle

Two contracts can reference each other so that each one's address depends on the other's. A contract's address commits to its constructor arguments and deployer, so when each address depends on the other neither can be computed first — a true cycle. (In the example: the shares token's `minter` is the vault, and the vault must learn its shares token address.)

Following the [cyclic-deployment standard](../../.supervision/circular_dep_deployer/agent_output.md), the cycle is broken by **deferring a minimal set of cross-references** out of the constructors. For a two-contract cycle exactly one edge is deferred:

- One contract — `linked` — keeps nothing cross-contract in its constructor and defers its back-reference into a one-shot, deployer-gated `set_<target>(AztecAddress)` setter. (The vault keeps only `asset` and `vault_offset`, and defers `set_shares_token`.)
- The other contract — `target` — keeps its reference in its constructor, because it is resolvable in dependency order: `linked` depends on nothing cross-contract, so it is derived first, and the derived `linked` address is then embedded as a constructor argument of `target`. (The shares token keeps `minter = vault` in its constructor.)

This leaves a single deferred edge (`linked`'s setter), which the deployer enforces on-chain. The two contracts are named by this deferred-link role rather than any parent/child hierarchy: `linked` is the contract whose setter is wired, and `target` is the contract whose derived address is injected into it.

## A reusable, spec-independent deployer

`publish_contract_instance_for_public_execution` is private-only, so the deploy-and-wire choreography must run inside a private function. `CyclicDeployer` follows the standard's core design decision: **`deploy` is an ordinary private function, not a constructor.** Because the deploy logic does not live in the deployer's initializer, the deployer instance's address does not depend on the contracts it deploys — so a single published `CyclicDeployer` instance can deploy any number of pairs, with the per-deployment `salt` acting as the sole address disambiguator.

This contract is intentionally **specific to the two-contract topology** (exactly two contracts, one deferred setter, and up to one optional action per contract) rather than the standard's fully generic N-contract form that accepts arbitrary contracts and index-referenced links. It does, however, adopt the standard's **hash-based dispatch model** and its data shapes, so it is fully **type-agnostic**:

- Each contract's constructor is described by a `ContractSpec { class_id, init_selector, init_args_hash, init_calldata_hash }`. The SDK precomputes the `init_args_hash` (which drives the contract's address) and the `init_calldata_hash` (which dispatches the public constructor), and the deployer treats both opaquely — it never constructs calldata from typed arguments.
- The deferred edge is described by a `Link { setter_selector }`. The deployer dispatches `linked`'s setter by this runtime selector, building the derived `target` address into the calldata in-circuit, so it needs no compile-time-typed setter stub.

A consequence of opaque dispatch is that any cross-reference kept in a constructor (`target` embedding `linked`) is resolved **off-chain**: the SDK derives `linked` first and embeds it when computing `target`'s hashes. The on-chain guarantee is therefore limited to the deferred link, whose argument is the address the deployer itself derived — so the `linked → target` link is enforced in-circuit while a `target → linked` constructor reference is SDK-trusted. This matches the generic standard, which is type-agnostic and cannot inspect constructor arguments.

In one transaction, `deploy`:

1. Derives both contract addresses on-chain from each `ContractSpec`'s `class_id` + `init_selector` + `init_args_hash` and the deployment salt, with this `CyclicDeployer` instance set as their (non-universal) `deployer`. `linked` is derived before `target` so `target`'s constructor may embed `linked`.
2. Calls `publish_contract_instance_for_public_execution` for both instances.
3. Runs both public constructors by dispatching their precomputed `init_calldata_hash` (with `hide_msg_sender = false`, so each constructor sees this contract as `msg_sender`).
4. Wires the deferred link by calling the `Link`'s `setter_selector` on `linked` with the derived `target` address, built in-circuit.
5. Optionally runs one authorized `Action` per contract after wiring — `linked_action` on `linked`, then `target_action` on `target`. Each action is enqueued only when its `calldata_hash` is non-zero, so a deployment with no actions, one action, or two actions all go through the same `deploy` entrypoint.

The derive/publish/construct work is shared by a single `_deploy_contract` helper that handles one contract from its `ContractSpec`; `deploy` calls it once per contract.

Each `Action` is opaque (its arguments are SDK-supplied via the calldata preimage); the target contract enforces its own one-shot / authorization semantics, so the deployer needs no knowledge of the action's arguments. (In the example: the vault's `initial_deposit` as the `linked_action`, whose `init_args_hash` must commit to `initial_deposit_pending = true` to arm that one-shot action.) Richer choreography — multiple actions on the same contract, or a defined order beyond linked-then-target — is intentionally left to the generic N-contract deployer or to an integrator's own action entrypoint.

Because both contracts record this `CyclicDeployer` instance as their non-universal `deployer`, and every contract call runs with this contract as `msg_sender`, the protocol's public initialization check, `publish_contract_instance_for_public_execution`, and the deferred setter's deployer-gate all pass.

## Inputs

```rust
/// @notice Opaque constructor-dispatch spec for one contract of the deployment.
struct ContractSpec {
    class_id: ContractClassId, // registered class to instantiate
    init_selector: Field,      // public constructor selector (drives the initialization hash)
    init_args_hash: Field,     // hash of the constructor ARGS; drives the contract address
    init_calldata_hash: Field, // hash of [selector, ..args]; dispatches the public constructor
}

/// @notice Deferred cross-reference wired after construction, enforced on-chain.
struct Link {
    setter_selector: Field,    // linked's setter to invoke (e.g. set_shares_token)
}

/// @notice Optional authorized side effect run on a single contract after wiring.
struct Action {
    calldata_hash: Field,      // hash of [selector, ..args]; zero = no action, else dispatched opaquely
}
```

## Functions

### deploy

```rust
/// @notice Atomically deploys and wires two cyclically-dependent contracts, optionally running one
///         authorized action on each after wiring
/// @dev Each action is an opaque public call dispatched by calldata hash; a zero `calldata_hash` means
///      "no action" and is skipped. Actions run after wiring, `linked` before `target`, each with this
///      contract as `msg_sender` so the target's deployer gate passes. Any authwit an action relies on
///      must be prepared by the SDK against the precomputed address before this tx.
/// @param salt The salt used to derive both contract addresses (must be unique per deployment)
/// @param linked The contract whose setter is wired by `link` (it defers a cross-reference)
/// @param target The contract whose derived address is injected into `linked`'s setter; its constructor may embed `linked`
/// @param link The deferred link to wire (`linked`'s `set_<target>` setter)
/// @param linked_action Optional action dispatched on `linked` after wiring (skipped when its `calldata_hash` is zero)
/// @param target_action Optional action dispatched on `target` after wiring (skipped when its `calldata_hash` is zero)
#[external("private")]
fn deploy(
    salt: Field,
    linked: ContractSpec,
    target: ContractSpec,
    link: Link,
    linked_action: Action,
    target_action: Action,
) { /* ... */ }
```

## Usage Notes

- Publish the participating contract classes (e.g. `Vault`, `Token`) and the `CyclicDeployer` class once per network, and publish a `CyclicDeployer` instance once. The same instance can be reused for every deployment.
- The SDK is responsible for the off-chain half of the choreography. For each contract it assembles a `ContractSpec` from the `class_id`, the constructor selector, the `init_args_hash` (`hash_args(args)`), and the `init_calldata_hash` (`hash_calldata_array([selector, ...args])`) — embedding the derived `linked` address into `target`'s constructor arguments — and a `Link` from `linked`'s setter selector. For each contract it wants to act on, it assembles an `Action` from the action's calldata hash (`hash_calldata_array([selector, ...args])`); for a contract with no action it passes an `Action` with a zero `calldata_hash`. It must then:
  - register both contract instance preimages with the PXE before submitting the transaction, so the `get_contract_instance` oracle can resolve them during publication; and
  - supply both constructor calldata preimages — plus the calldata preimage of each non-zero action — as **extra hashed args** on the transaction, so the deployer's hash-dispatched public calls resolve.
- Both contract instances use the `CyclicDeployer` instance as their `deployer` and reuse the deployment `salt` as their own salt. Their addresses can therefore be precomputed off-chain from the `CyclicDeployer` instance address, the deployment salt, the corresponding `ContractClassId`, and the corresponding initialization hash (derived from the constructor selector and `init_args_hash`). Precomputing a contract's address is required when its action relies on an authwit signed against it (e.g. the vault's initial deposit on `linked`).
- Use a fresh, unpredictable `salt` per deployment. Under a reused `CyclicDeployer` instance the `deployer` field is constant, so the salt is the only thing that keeps each pair's addresses distinct.
