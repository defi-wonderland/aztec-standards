use aztec::macros::aztec;

/// @title CyclicDeployer
/// @notice Atomically deploys and wires two cyclically-dependent contracts in a single transaction,
///         breaking the deploy-time cycle between them.
/// @dev Two contracts can reference each other so that each one's address depends on the other's -- a true
///      cycle, since an address commits to its constructor arguments and deployer. The cycle is broken by
///      deferring ONE side's cross-reference out of its constructor into a one-shot, deployer-gated setter
///      `set_<target>(AztecAddress)`; the other side keeps its reference in its constructor, resolvable in
///      dependency order.
///
///      This deployer follows the cyclic-deployment standard's dispatch model, specialised to the fixed
///      two-contract topology. It is fully type-agnostic -- it imports none of the contracts it deploys:
///        - Constructors are dispatched by precomputed calldata hashes (`ContractSpec`). The SDK computes,
///          per contract, the `init_args_hash` (drives the address) and `init_calldata_hash` (drives the
///          public dispatch), and the deployer treats both opaquely.
///        - The deferred link is dispatched by a runtime selector (`Link`), with the derived target
///          address built into the calldata in-circuit.
///
///      The two contracts are named by their deferred-link role: `linked` is the contract whose setter is
///      wired (it defers its cross-reference), and `target` is the contract whose derived address is injected
///      into that setter. Because constructor calldata is opaque, any cross-reference kept in a constructor
///      (the `target` embedding `linked`'s address) is resolved OFF-CHAIN: the SDK derives `linked` first and
///      embeds it when computing `target`'s hashes. The on-chain guarantee is limited to the deferred link,
///      whose argument is the address THIS contract derived, so the `linked -> target` link is enforced
///      in-circuit while a `target -> linked` constructor reference is SDK-trusted. This mirrors the generic
///      standard, which is type-agnostic and cannot inspect constructor arguments.
///
///      `deploy` is an ordinary private function (NOT a constructor), so this instance's address does not
///      depend on the contracts it deploys. One published `CyclicDeployer` instance can deploy any number of
///      pairs; the per-deployment `salt` is the sole address disambiguator. In one transaction `deploy`:
///        1. derives both contract addresses on-chain, with this instance as their deployer,
///        2. publishes both instances for public execution,
///        3. runs both public constructors by dispatching their precomputed calldata hashes,
///        4. wires the deferred link by calling `linked`'s setter with `target`'s derived address, and
///        5. optionally runs one authorized action per contract (each enqueued only when its calldata hash is
///           non-zero), so a deployment with no actions and a deployment with up to two actions share one entrypoint.
///
///      Both contracts record THIS instance as their non-universal `deployer`, and every contract call runs
///      with this contract as `msg_sender`, which is what lets the protocol's public initialization check,
///      `publish_contract_instance_for_public_execution`, and the deferred setter's deployer gate pass.
///
///      The SDK must register both instance preimages with the PXE before the tx (so the
///      `get_contract_instance` oracle can resolve them during publication) and supply the constructor
///      (and any action) calldata preimages as extra hashed args (so the dispatched-by-hash calls resolve).
#[aztec]
pub contract CyclicDeployer {
    use aztec::{
        macros::functions::{external, initialization_utils::compute_initialization_hash, internal},
        protocol::{
            abis::function_selector::FunctionSelector, address::AztecAddress,
            contract_class_id::ContractClassId, contract_instance::ContractInstance,
            public_keys::PublicKeys, traits::{Deserialize, FromField, Serialize, ToField},
        },
        publish_contract_instance::publish_contract_instance_for_public_execution,
    };

    /// @notice Opaque constructor-dispatch spec for one contract of the deployment.
    /// @dev The deployer derives the contract address from `class_id` + `init_selector` +
    ///      `init_args_hash`, and dispatches its public constructor by `init_calldata_hash`. All
    ///      four are caller-supplied and treated opaquely; the SDK is responsible for their consistency (e.g.
    ///      embedding a derived target address as a constructor argument, resolved in dependency order).
    #[derive(Serialize, Deserialize)]
    pub struct ContractSpec {
        pub class_id: ContractClassId,
        pub init_selector: Field,
        pub init_args_hash: Field,
        pub init_calldata_hash: Field,
    }

    /// @notice Deferred cross-reference wired after construction, enforced on-chain.
    /// @dev The link invokes `linked`'s setter with `target`'s derived address. For the fixed two-contract
    ///      topology the direction is implicit (`linked` defers its reference to `target`), so only the setter
    ///      selector is configurable. The setter's target argument is injected by the deployer in-circuit from
    ///      the address it derived, so an off-chain script cannot substitute it.
    #[derive(Serialize, Deserialize)]
    pub struct Link {
        pub setter_selector: Field,
    }

    /// @notice Optional authorized side effect run on a single contract after wiring.
    /// @dev Opaque to the deployer: dispatched by precomputed calldata hash, with the preimage supplied by the
    ///      SDK as an extra hashed arg. A `calldata_hash` of zero means "no action" and is skipped; any other
    ///      value enqueues the call. The target contract enforces its own one-shot / authorization semantics,
    ///      so the deployer treats the action as fully opaque. `deploy` accepts one `Action` per contract;
    ///      richer choreography (multiple actions on the same contract, or a defined order beyond
    ///      linked-then-target) is out of scope for this specialization -- use the generic N-contract deployer.
    #[derive(Serialize, Deserialize)]
    pub struct Action {
        pub calldata_hash: Field,
    }

    /// @notice Atomically deploys and wires two cyclically-dependent contracts, optionally running one
    ///         authorized action on each after wiring.
    /// @dev Each action is an opaque public call dispatched by calldata hash; a zero `calldata_hash` means
    ///      "no action" and is skipped. Actions run after wiring, `linked` before `target`, each with this
    ///      contract as `msg_sender` so the target's deployer gate passes; each contract enforces its own
    ///      one-shot / authorization semantics. Any authwit an action relies on must be prepared by the SDK
    ///      against the precomputed address before this tx.
    /// @param salt The salt used to derive both contract addresses (must be unique per deployment).
    /// @param linked The contract whose setter is wired by `link` (it defers a cross-reference).
    /// @param target The contract whose derived address is injected into `linked`'s setter; its constructor may embed `linked`.
    /// @param link The deferred link to wire (`linked`'s `set_<target>` setter).
    /// @param linked_action Optional action dispatched on `linked` after wiring (skipped when its `calldata_hash` is zero).
    /// @param target_action Optional action dispatched on `target` after wiring (skipped when its `calldata_hash` is zero).
    #[external("private")]
    fn deploy(
        salt: Field,
        linked: ContractSpec,
        target: ContractSpec,
        link: Link,
        linked_action: Action,
        target_action: Action,
    ) {
        let linked_address = self.internal._deploy_contract(salt, linked);
        let target_address = self.internal._deploy_contract(salt, target);

        // Wire the deferred link: `linked` learns its co-deployed `target`. The argument is the address this
        // contract derived, built into the calldata in-circuit, so the link is enforced; the setter is
        // one-shot and deployer-gated (it runs with this contract as `msg_sender`).
        self.context.call_public_function(
            linked_address,
            FunctionSelector::from_field(link.setter_selector),
            [target_address.to_field()],
            false,
        );

        // Run each optional action after wiring, `linked` before `target`. A zero calldata hash means no
        // action, so each call is enqueued only for a non-zero hash.
        self.internal._run_action(linked_address, linked_action);
        self.internal._run_action(target_address, target_action);
    }

    /** ==========================================================
     * ====================== INTERNALS ==========================
     * ======================================================== */

    /// @notice Derives a contract's address, publishes its instance, and dispatches its constructor.
    /// @dev Called once per contract. The constructor is dispatched by its precomputed calldata hash (opaque to
    ///      this contract); the SDK supplies the matching calldata preimage. The contract uses this instance as
    ///      its (non-universal) deployer, which the protocol's public initialization check enforces against
    ///      `msg_sender`. Publishes run in private and so always precede every public constructor; `linked` is
    ///      deployed before `target` so `target`'s constructor may embed `linked`'s address.
    /// @return The derived contract address.
    #[internal("private")]
    fn _deploy_contract(salt: Field, spec: ContractSpec) -> AztecAddress {
        // 1. Derive the contract address on-chain, with this instance as the deployer.
        let address =
            _derive_instance(spec.init_selector, spec.init_args_hash, spec.class_id, salt, self.address);

        // 2. Publish the instance (reverts on a duplicate or already-published address).
        publish_contract_instance_for_public_execution(context, address);

        // 3. Run the public constructor by dispatching its precomputed calldata hash. `hide_msg_sender` is
        //    false so the constructor sees this contract as `msg_sender`, satisfying the deployer check.
        context.call_public_function_with_calldata_hash(address, spec.init_calldata_hash, false, false);

        address
    }

    /// @notice Dispatches an optional action on a single contract after wiring.
    /// @dev A zero `calldata_hash` means "no action", so the public call is enqueued only for a non-zero hash.
    ///      The action is opaque (dispatched by calldata hash) and runs with this contract as `msg_sender`, so
    ///      the target's deployer gate passes; the target enforces its own one-shot / authorization semantics.
    /// @param address The contract to dispatch the action on.
    /// @param action The optional action (skipped when its `calldata_hash` is zero).
    #[internal("private")]
    fn _run_action(address: AztecAddress, action: Action) {
        if action.calldata_hash != 0 {
            context.call_public_function_with_calldata_hash(address, action.calldata_hash, false, false);
        }
    }

    /// @notice Derives a contract instance address from its class, salt, constructor, and deployer.
    #[contract_library_method]
    fn _derive_instance(
        init_selector: Field,
        init_args_hash: Field,
        contract_class_id: ContractClassId,
        salt: Field,
        deployer: AztecAddress,
    ) -> AztecAddress {
        let initialization_hash = compute_initialization_hash(
            FunctionSelector::from_field(init_selector),
            init_args_hash,
        );

        ContractInstance {
            salt,
            deployer,
            contract_class_id,
            initialization_hash,
            public_keys: PublicKeys::default(),
        }
            .to_address()
    }
}
