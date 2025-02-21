use dep::aztec::macros::aztec;

// Authorizer implementation with Merkle proof verification
#[aztec]
pub contract MerkleInclussionAuthorizer {

    use dep::aztec::protocol_types::constants::MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS;

    use dep::aztec::{
        macros::{functions::{initializer, private, public, view}, storage::storage},
        prelude::{AztecAddress, Map, PublicMutable},
    };

    #[storage]
    struct Storage<Context> {
        owner: PublicMutable<AztecAddress, Context>,
        root_hash: PublicMutable<Field, Context>,
        whitelist: Map<AztecAddress, PublicMutable<bool, Context>, Context>,
    }

    #[public]
    #[initializer]
    fn constructor(_owner: AztecAddress) {
        storage.owner.write(_owner);
    }

    /** ==========================================================
    * ========================= PRIVATE =========================
    * ======================================================== */
    #[private]
    fn authorize_in_private(sender: AztecAddress, recipient: AztecAddress, amount: U128) {
        let merkle_tree_proof: [Field; MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS] =
            [0; MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS];

        // TODO: Pop capsule
        // merkle_tree_proof = unsafe { pop_capsule() };

        // TODO: Can we have the msg.sig for this method?

        let is_sender_valid = _verify_merkle_proof(sender, merkle_tree_proof);

        assert(is_sender_valid, "Sender is not authorized");
    }

    /** ==========================================================
    * ========================= PUBLIC ==========================
    * ======================================================== */

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

