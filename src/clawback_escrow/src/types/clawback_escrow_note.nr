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
        traits::{Empty, Packable, Serialize, ToField},
    },
};

#[note]
#[derive(Serialize)]
pub struct ClawbackEscrowNote {
    sender: AztecAddress,
    receiver: AztecAddress,
    escrow: AztecAddress,
    randomness: Field,
}

impl NullifiableNote for ClawbackEscrowNote {
    fn compute_nullifier(self, _: &mut PrivateContext, note_hash_for_nullify: Field) -> Field {
        poseidon2_hash_with_separator(
            [note_hash_for_nullify, self.escrow.to_field()],
            GENERATOR_INDEX__NOTE_NULLIFIER as Field,
        )
    }

    unconstrained fn compute_nullifier_without_context(self) -> Field {
        let note_hash_for_nullify = compute_note_hash_for_nullify(self);
        poseidon2_hash_with_separator(
            [note_hash_for_nullify, self.escrow.to_field()],
            GENERATOR_INDEX__NOTE_NULLIFIER as Field,
        )
    }
}

impl Eq for ClawbackEscrowNote {
    fn eq(self: Self, other: Self) -> bool {
        (self.escrow.to_field() == other.escrow.to_field())
    }
}

impl ClawbackEscrowNote {
    pub fn new(sender: AztecAddress, receiver: AztecAddress, escrow: AztecAddress) -> Self {
        let randomness = unsafe { random() };
        ClawbackEscrowNote { sender, receiver, escrow, randomness, header: NoteHeader::empty() }
    }
}

