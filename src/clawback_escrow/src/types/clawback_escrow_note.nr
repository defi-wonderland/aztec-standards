use dep::aztec::{
    context::PrivateContext,
    macros::notes::custom_note,
    note::{note_interface::NoteHash, utils::compute_note_hash_for_nullify},
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::{
        constants::{GENERATOR_INDEX__NOTE_HASH, GENERATOR_INDEX__NOTE_NULLIFIER},
        hash::poseidon2_hash_with_separator,
        traits::{Empty, Packable, Serialize, ToField},
        utils::arrays::array_concat,
    },
};

#[custom_note]
#[derive(Serialize)]
pub struct ClawbackEscrowNote {
    sender: AztecAddress,
    receiver: AztecAddress,
    escrow: AztecAddress,
    randomness: Field,
}

impl NoteHash for ClawbackEscrowNote {
    fn compute_note_hash(self, storage_slot: Field) -> Field {
        let inputs = array_concat(self.pack(), [storage_slot]);
        poseidon2_hash_with_separator(inputs, GENERATOR_INDEX__NOTE_HASH)
    }

    fn compute_nullifier(self, _: &mut PrivateContext, note_hash_for_nullify: Field) -> Field {
        poseidon2_hash_with_separator(
            [note_hash_for_nullify, self.escrow.to_field()],
            GENERATOR_INDEX__NOTE_NULLIFIER as Field,
        )
    }

    unconstrained fn compute_nullifier_unconstrained(self, note_hash_for_nullify: Field) -> Field {
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
        ClawbackEscrowNote { sender, receiver, escrow, randomness }
    }
}
