use dep::aztec::{
    context::PrivateContext,
    macros::notes::note,
    note::{
        note_header::NoteHeader, note_interface::NullifiableNote,
        utils::compute_note_hash_for_nullify,
    },
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

impl NullifiableNote for AccountNote {
    fn compute_nullifier(self, _: &mut PrivateContext, note_hash_for_nullify: Field) -> Field {
        poseidon2_hash_with_separator(
            [note_hash_for_nullify],
            GENERATOR_INDEX__NOTE_NULLIFIER as Field,
        )
    }

    unconstrained fn compute_nullifier_without_context(self) -> Field {
        let note_hash_for_nullify = compute_note_hash_for_nullify(self);
        poseidon2_hash_with_separator(
            [note_hash_for_nullify],
            GENERATOR_INDEX__NOTE_NULLIFIER as Field,
        )
    }
}

impl AccountNote {
    pub fn new(owner: AztecAddress, secret: Field) -> Self {
        let randomness = unsafe { random() };
        AccountNote { owner, secret, randomness, header: NoteHeader::empty() }
    }
}

