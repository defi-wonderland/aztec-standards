use dep::aztec::{
    context::PrivateContext,
    keys::getters::{get_nsk_app, get_public_keys},
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
pub struct TransferAccumulatorNote {
    from: AztecAddress,
    accumulated: U128,
    randomness: Field,
    nonce: U128,
}

impl NullifiableNote for TransferAccumulatorNote {
    fn compute_nullifier(
        self,
        context: &mut PrivateContext,
        note_hash_for_nullify: Field,
    ) -> Field {
        let owner_npk_m_hash = get_public_keys(self.from).npk_m.hash();
        let secret = context.request_nsk_app(owner_npk_m_hash);
        poseidon2_hash_with_separator(
            [note_hash_for_nullify, secret, self.nonce.to_field()],
            GENERATOR_INDEX__NOTE_NULLIFIER as Field,
        )
    }

    unconstrained fn compute_nullifier_without_context(self) -> Field {
        let note_hash_for_nullify = compute_note_hash_for_nullify(self);
        let owner_npk_m_hash = get_public_keys(self.from).npk_m.hash();
        let secret = get_nsk_app(owner_npk_m_hash);
        poseidon2_hash_with_separator(
            [note_hash_for_nullify, secret, self.nonce.to_field()],
            GENERATOR_INDEX__NOTE_NULLIFIER as Field,
        )
    }
}
impl Eq for TransferAccumulatorNote {
    fn eq(self: Self, other: Self) -> bool {
        (self.from == other.from) & (self.accumulated == other.accumulated)
    }
}

impl TransferAccumulatorNote {
    pub fn new(from: AztecAddress, accumulated: U128, nonce: U128) -> Self {
        let randomness = unsafe { random() };
        TransferAccumulatorNote {
            from,
            accumulated,
            randomness,
            nonce,
            header: NoteHeader::empty(),
        }
    }
}

