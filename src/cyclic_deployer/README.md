# Cyclic Deployer Contract

`CyclicDeployer` deploys and wires **two contracts that depend on each other** in a single transaction. It is type-agnostic — it imports none of the contracts it deploys — so any mutually-dependent pair can reuse the same deployer.

The worked example throughout is the [`Vault`](../vault_contract) and its shares [`Token`](../token_contract): the token's `minter` is the vault, and the vault needs the token's address (see the vault [Deployment Guide](../vault_contract/README.md#deployment-guide)).

## The problem

A contract's address is derived from its constructor arguments and its deployer. When two contracts each take the other's address as a constructor argument, neither address can be computed first — a deploy-time cycle.

## How it breaks the cycle

The cycle is broken on one side, giving the two contracts their names:

- **`linked`** keeps no cross-contract reference in its constructor. Instead it exposes a setter (e.g. `set_shares_token`) that the deployer calls _after_ construction. Its address doesn't depend on the other contract, so it can be derived first.
- **`target`** embeds `linked`'s already-derived address directly in its constructor. 

The deployer then completes the link by calling `linked`'s setter with `target`'s address.

## What `deploy` does

`deploy` is a regular private function, so one published `CyclicDeployer` instance can deploy any number of pairs — a fresh `salt` per deployment keeps their addresses distinct. In a single transaction it:

1. Derives both addresses, with the deployer instance as their `deployer`.
2. Publishes both contract instances.
3. Runs both constructors.
4. Calls `linked`'s setter with `target`'s derived address.
5. Optionally runs one action per contract (`linked`, then `target`), skipping any whose `calldata_hash` is zero.

Everything is dispatched **by hash**, which is what keeps the deployer type-agnostic: constructors and actions are precomputed calldata hashes, and the link is just a setter selector. The SDK supplies the matching preimages (see [Using it](#using-it)).

## Interface

```rust
/// Constructor-dispatch spec for one contract, all treated opaquely.
struct ContractSpec {
    class_id: ContractClassId, // registered class to instantiate
    init_selector: Field,      // public constructor selector
    init_args_hash: Field,     // hash of the constructor args; drives the contract address
    init_calldata_hash: Field, // hash of [selector, ..args]; dispatches the constructor
}

/// The deferred reference wired on `linked` after construction.
struct Link {
    setter_selector: Field,    // linked's setter to call (e.g. set_shares_token)
}

/// An optional side effect dispatched on one contract after wiring.
struct Action {
    calldata_hash: Field,      // hash of [selector, ..args]; zero = no action
}

/// Deploys and wires `linked` + `target`, then runs each non-zero action (`linked` before `target`).
#[external("private")]
fn deploy(
    salt: Field,             // unique per deployment
    linked: ContractSpec,    // its setter is wired by `link`
    target: ContractSpec,    // its derived address is injected into `linked`'s setter
    link: Link,
    linked_action: Action,   // runs on `linked`  (skip with a zero calldata_hash)
    target_action: Action,   // runs on `target`  (skip with a zero calldata_hash)
) { /* ... */ }
```

## What it guarantees (and what it doesn't)

On-chain, the deployer guarantees only that:

- both contracts are deployed with the `CyclicDeployer` instance as their `deployer`, and
- `linked`'s setter is called with the `target` address the deployer derived itself (it can't be swapped off-chain), with the deployer instance as `msg_sender`.

It does **not** enforce any application logic on the deployed contracts. The contracts themselves must therefore:

- **gate the setter to their deployer** — otherwise anyone could call it and wire a different `target`;
- **make the setter one-shot** if the link must not change later — the deployer won't prevent a second call;
- **enforce each action's own authorization / one-shot rules** — actions are opaque to the deployer (e.g. the vault's `initial_deposit` is gated by an `initial_deposit_pending` flag baked into its address).

A constructor reference in the other direction (`target → linked`) is computed off-chain by the SDK and **not** enforced on-chain. Verify it from public state after deployment (e.g. that the shares token's `minter` is the vault).

## Using it

Publish the contract classes (e.g. `Vault`, `Token`) and the `CyclicDeployer` class once per network, and publish one `CyclicDeployer` instance to reuse for every deployment. Then, off-chain, the SDK must:

- build a `ContractSpec` per contract, embedding `linked`'s derived address into `target`'s constructor args;
- build a `Link` from `linked`'s setter selector, and an `Action` per contract (zero `calldata_hash` = no action);
- register both contract instances with the PXE so they resolve during publication; and
- attach every constructor and non-zero action calldata preimage as **extra hashed args**, so the hash-dispatched calls resolve.

Use a fresh, unpredictable `salt` per deployment — with a reused deployer instance, the salt is the only thing keeping each pair's addresses distinct. Precompute a contract's address ahead of time when an action needs an authwit signed against it (e.g. the vault's initial deposit).
