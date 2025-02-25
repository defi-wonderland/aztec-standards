
use dep::aztec::macros::aztec;

// Minimal authorization token implementation that supports `AuthWit` accounts.
// The authorization for transfers is done via a merkle proof of inclusion that is managed by the owner.
// The owner can add and remove addresses from the whitelist at any time.
// The auth message follows a similar pattern to the cross-chain message and includes a designated caller.
// The designated caller is ALWAYS used here, and not based on a flag as cross-chain.
// message hash = H([caller, contract, selector, ...args])
// To be read as `caller` calls function at `contract` defined by `selector` with `args`
// Including a nonce in the message hash ensures that the message can only be used once.
#[aztec]
pub contract MerkleInclusionAuthorizerToken {

    use dep::aztec::protocol_types::constants::MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS;

    // Libs
    use dep::aztec::{
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
        prelude::{AztecAddress, PublicMutable, Map},
        protocol_types::{traits::Serialize},
    };

    #[storage]
    struct Storage<Context> {
        owner: PublicMutable<AztecAddress, Context>,
        root_hash: PublicMutable<Field, Context>,
        whitelist: Map<AztecAddress, PublicMutable<bool, Context>, Context>,
    }

    #[public]
    #[initializer]
    fn constructor(name: str<31>, symbol: str<31>, decimals: u8, owner: AztecAddress) {
        storage.owner.write(owner);
    }

    /** ==========================================================
     * ========================= PRIVATE =========================
     * ======================================================== */
    #[private]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        authorize_in_private(from, to, amount);
        // ...
    }

    #[private]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        authorize_in_private(from, to, amount);
        // ...
    }

    // Transfers token `amount` from public balance of message sender to a private balance of `to`.
    #[private]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        authorize_in_private(from, to, amount);
        // ...
    }
    /// Prepares an increase of private balance of `to` (partial note). The increase needs to be finalized by calling
    /// some of the finalization functions (`finalize_transfer_public_to_private`, `finalize_mint_to_private`).
    /// Returns a hiding point slot.
    #[private]
    fn prepare_transfer_public_to_private(to: AztecAddress, from: AztecAddress) -> Field {
        // ...
    }

    /** ==========================================================
     * ========================= PUBLIC ==========================
     * ======================================================== */

    #[public]
    fn transfer_public_to_public(from: AztecAddress, to: AztecAddress, amount: U128, nonce: Field) {
        // ...
        authorize_in_public(from, to, amount);
        // ...
    }

    /// Finalizes a transfer of token `amount` from public balance of `from` to a private balance of `to`.
    /// The transfer must be prepared by calling `prepare_transfer_public_to_private` first and the resulting
    /// `hiding_point_slot` must be passed as an argument to this function.
    #[public]
    fn finalize_transfer_public_to_private(
        from: AztecAddress,
        amount: U128,
        hiding_point_slot: Field,
        nonce: Field,
    ) {
        // ...
    }

    /// This is a wrapper around `_finalize_transfer_public_to_private` placed here so that a call
    /// to `_finalize_transfer_public_to_private` can be enqueued. Called unsafe as it does not check `from` (this has to be
    /// done in the calling function).
    #[public]
    #[internal]
    fn _finalize_transfer_public_to_private_unsafe(
        from: AztecAddress,
        amount: U128,
        hiding_point_slot: Field,
    ) {
        // ...
    }

    /** ==========================================================
     * ======================= AUTHORIZATION =====================
     * ======================================================== */

    #[contract_library_method]
    fn authorize_in_private(from: AztecAddress, to: AztecAddress, amount: U128) {
        let merkle_tree_proof: [Field; MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS] =
            [0; MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS];

        // TODO: Pop capsule
        // merkle_tree_proof = unsafe { pop_capsule() };

        // TODO: Can we have the msg.sig for this method?

        let is_from_valid = _verify_merkle_proof(from, merkle_tree_proof);

        assert(is_from_valid, "Sender is not authorized");
    }

    #[public]
    #[view]
    fn root_hash() -> Field {
        storage.root_hash.read()
    }

    #[public]
    fn validate_root_hash(_root_hash: Field) {
        assert(_root_hash == storage.root_hash.read(), "Invalid root hash");
    }

    #[public]
    fn add_to_whitelist(address: AztecAddress, root_hash: Field) {
        assert(storage.owner.read() == context.msg_sender(), "Not owner");
        storage.whitelist.at(address).write(true);
        storage.root_hash.write(root_hash);
    }

    #[public]
    fn remove_from_whitelist(address: AztecAddress, root_hash: Field) {
        assert(storage.owner.read() == context.msg_sender(), "Not owner");
        storage.whitelist.at(address).write(false);
        storage.root_hash.write(root_hash);
    }

    #[public]
    fn authorize_in_public(from: AztecAddress, to: AztecAddress, amount: U128) {
        assert(storage.whitelist.at(from).read(), "Not whitelisted");
    }

    /** ==========================================================
    * ======================= LIBRARIES =========================
    * ======================================================== */

    #[contract_library_method]
    fn _verify_merkle_proof(
        address: AztecAddress,
        proof: [Field; MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS],
    ) -> bool {
        // TODO: Use the merkle proof to verify the address is in the merkle tree
        // calculate root hash
        // let _root_hash = ...;
        // let self = MerkleInclussionAuthorizer::at(context.this_address());
        // self.validate_root_hash(_root_hash);
        true
    }
}

