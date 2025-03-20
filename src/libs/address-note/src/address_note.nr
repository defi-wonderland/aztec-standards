use dep::aztec::{
    context::PrivateContext,
    keys::getters::{get_nsk_app, get_public_keys},
    macros::notes::note,
    note::utils::compute_note_hash_for_nullify,
    oracle::random::random,
    protocol_types::{
        address::AztecAddress,
        constants::GENERATOR_INDEX__NOTE_NULLIFIER,
        hash::poseidon2_hash_with_separator,
        traits::{Packable, Serialize},
    },
};

// Stores an address
#[note]
#[derive(Serialize)]
pub struct AddressNote {
    address: AztecAddress,
    owner: AztecAddress,
    randomness: Field,
}

impl AddressNote {
    pub fn new(address: AztecAddress, owner: AztecAddress) -> Self {
        /** Safety: We use the randomness to preserve the privacy of the note recipient by preventing brute-forcing, so a
         *  malicious sender could use non-random values to make the note less private. But they already know the full
         *  note pre-image anyway, and so the recipient already trusts them to not disclose this information. We can
         *  therefore assume that the sender will cooperate in the random value generation. */
        let randomness = unsafe { random() };
        AddressNote { address, owner, randomness }
    }
}

impl Eq for AddressNote {
    fn eq(self, other: Self) -> bool {
        (self.address == other.address)
            & (self.owner == other.owner)
            & (self.randomness == other.randomness)
    }
}
