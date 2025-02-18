mod types;
mod test;

use dep::aztec::macros::aztec;

// Minimal token implementation that supports `AuthWit` accounts.
// The auth message follows a similar pattern to the cross-chain message and includes a designated caller.
// The designated caller is ALWAYS used here, and not based on a flag as cross-chain.
// message hash = H([caller, contract, selector, ...args])
// To be read as `caller` calls function at `contract` defined by `selector` with `args`
// Including a nonce in the message hash ensures that the message can only be used once.
#[aztec]
pub contract Verifier {

    use dep::capsule::pop_capsule;
    use dep::aztec::protocol_types::{
        constants::{
            MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS,
        },
    };

        #[storage]
    struct Storage<Context> {
        root_hash: PublicMutable<Field, Context>,
    }

   /** ==========================================================
    * ========================= PRIVATE =========================
    * ======================================================== */
    #[private]
    fn validate_from_private(
        sender: AztecAddress,
        recipient: AztecAddress,
        amount: U128
    ) {
        let merkle_tree_proof: [Field; MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS] =
            unsafe { pop_capsule() };

        let is_sender_valid = _verify_merkle_proof(sender, merkle_tree_proof, rootHash);

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


