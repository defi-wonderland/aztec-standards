use dep::aztec::macros::aztec;

// Verifier implementation with Merkle proof verification
#[aztec]
pub contract Verifier {

    use dep::aztec::protocol_types::{
        constants::{
            MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS,
        },
    };

    use dep::aztec::{
        macros::{functions::{private, public, view}, storage::storage},
        prelude::{AztecAddress, PublicMutable},
    };

    #[storage]
    struct Storage<Context> {
        root_hash: PublicMutable<Field, Context>,
    }

   /** ==========================================================
    * ========================= PRIVATE =========================
    * ======================================================== */
    #[private]
    fn verify_in_private(
        sender: AztecAddress,
        recipient: AztecAddress,
        amount: U128
    ) {
        let merkle_tree_proof: [Field; MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS] = [0; MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS];

        // TODO: Pop capsule
        // merkle_tree_proof = unsafe { pop_capsule() };

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

    /** ==========================================================
    * ======================= LIBRARIES =========================
    * ======================================================== */

    #[contract_library_method]
    fn _verify_merkle_proof(
        address: AztecAddress,
        proof: [Field; MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS]
    ) -> bool {
        // TODO: Use the merkle proof to verify the address is in the merkle tree
        // calculate root hash
        // let _root_hash = ...;
        // let self = Verifier::at(context.this_address());
        // self.validate_root_hash(_root_hash);
        true
    }
}


