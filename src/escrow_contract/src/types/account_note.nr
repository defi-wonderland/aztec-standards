use dep::aztec::{
    macros::notes::note,
    note::note_interface::NoteHash,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::{
        constants::GENERATOR_INDEX__NOTE_NULLIFIER,
        hash::poseidon2_hash_with_separator,
        traits::{Empty, Packable, Serialize},
    },
};

#[note]
#[derive(Serialize)]
pub struct AccountNote {
    owner: AztecAddress,
    secret: Field,
    randomness: Field,
}

impl AccountNote {
    pub fn new(owner: AztecAddress, secret: Field) -> Self {
        let randomness = unsafe { random() };
        AccountNote { owner, secret, randomness }
    }
}
