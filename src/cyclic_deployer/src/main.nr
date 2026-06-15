use aztec::macros::aztec;

/// @title CyclicDeployer
/// @notice Atomically deploys and wires two cyclically-dependent contracts in a single transaction.
/// @dev When two contracts reference each other, each one's address depends on the other's -- a cycle, since
///      an address commits to its constructor arguments and deployer. The cycle is broken by deferring one
///      side's cross-reference out of its constructor into a setter the deployer wires after construction; the
///      other side keeps its reference in its constructor, resolved in dependency order off-chain.
///
///      The deployer is type-agnostic: it imports none of the contracts it deploys. Constructors are
///      dispatched by precomputed calldata hashes (`ContractSpec`) and the deferred link by a runtime selector
///      (`Link`), both treated opaquely. `linked` is the contract whose setter is wired; `target` is the
///      contract whose derived address is injected into that setter. In one transaction `deploy` derives both
///      addresses (with this instance as their deployer), publishes both instances, runs their constructors,
///      wires the link, and optionally runs one action per contract.
///
///      See the README for the dispatch model, trust assumptions, and the off-chain SDK steps.
#[aztec]
pub contract CyclicDeployer {
    use aztec::{
        macros::functions::{external, initialization_utils::compute_initialization_hash, internal},
        protocol::{
            abis::function_selector::FunctionSelector,
            address::AztecAddress,
            contract_class_id::ContractClassId,
            contract_instance::ContractInstance,
            public_keys::PublicKeys,
            traits::{Deserialize, FromField, Serialize, ToField},
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

    /// @notice Deferred cross-reference wired on `linked` after construction.
    /// @dev Only the setter selector is configurable; the deployer calls it with `target`'s derived address,
    ///      built into the calldata in-circuit, so an off-chain caller cannot substitute the argument.
    #[derive(Serialize, Deserialize)]
    pub struct Link {
        pub setter_selector: Field,
    }

    /// @notice Optional side effect dispatched on a single contract after wiring.
    /// @dev Dispatched by precomputed calldata hash (the SDK supplies the preimage as an extra hashed arg) and
    ///      treated opaquely. A zero `calldata_hash` means "no action" and is skipped; any other value enqueues
    ///      the call.
    #[derive(Serialize, Deserialize)]
    pub struct Action {
        pub calldata_hash: Field,
    }

    /// @notice Atomically deploys and wires two cyclically-dependent contracts, optionally running one
    ///         action on each after wiring.
    /// @dev Derives both addresses with this instance as their deployer, publishes both, runs their
    ///      constructors, wires the link, then dispatches each non-zero action (`linked` before `target`).
    ///      Every call runs with this contract as `msg_sender`. The deployer makes no guarantees about the
    ///      deployed contracts beyond this; see the README for the assumptions a caller must satisfy.
    /// @param salt The salt used to derive both contract addresses (must be unique per deployment).
    /// @param linked The contract whose setter is wired by `link`.
    /// @param target The contract whose derived address is injected into `linked`'s setter; its constructor may embed `linked`.
    /// @param link The deferred link to wire on `linked`.
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

        // Wire the deferred link: call `linked`'s setter with `target`'s derived address. The argument is
        // built into the calldata in-circuit (it cannot be substituted off-chain) and the call runs with this
        // contract as `msg_sender`.
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
    /// @dev Called once per contract. The constructor is dispatched by its precomputed calldata hash; the SDK
    ///      supplies the matching preimage. This instance is recorded as the contract's deployer, which the
    ///      protocol's public initialization check enforces against `msg_sender`. Publishes run in private and
    ///      so always precede every public constructor; `linked` is deployed before `target` so `target`'s
    ///      constructor may embed `linked`'s address.
    /// @return The derived contract address.
    #[internal("private")]
    fn _deploy_contract(salt: Field, spec: ContractSpec) -> AztecAddress {
        // 1. Derive the contract address on-chain, with this instance as the deployer.
        let address = _derive_instance(
            spec.init_selector,
            spec.init_args_hash,
            spec.class_id,
            salt,
            self.address,
        );

        // 2. Publish the instance (reverts on a duplicate or already-published address).
        publish_contract_instance_for_public_execution(context, address);

        // 3. Run the public constructor by dispatching its precomputed calldata hash. `hide_msg_sender` is
        //    false so the constructor sees this contract as `msg_sender` (the recorded deployer).
        context.call_public_function_with_calldata_hash(
            address,
            spec.init_calldata_hash,
            false,
            false,
        );

        address
    }

    /// @notice Dispatches an optional action on a single contract after wiring.
    /// @dev A zero `calldata_hash` means "no action", so the public call is enqueued only for a non-zero hash.
    ///      The action is dispatched opaquely by calldata hash and runs with this contract as `msg_sender`.
    /// @param address The contract to dispatch the action on.
    /// @param action The optional action (skipped when its `calldata_hash` is zero).
    #[internal("private")]
    fn _run_action(address: AztecAddress, action: Action) {
        if action.calldata_hash != 0 {
            context.call_public_function_with_calldata_hash(
                address,
                action.calldata_hash,
                false,
                false,
            );
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
