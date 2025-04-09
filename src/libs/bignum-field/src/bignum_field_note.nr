use aztec::{
    context::{PrivateContext, PublicContext},
    keys::getters::{get_nsk_app, get_public_keys},
    macros::notes::custom_note,
    note::note_interface::{NoteHash, NoteType},
    oracle::random::random,
    protocol_types::{
        address::AztecAddress,
        constants::{GENERATOR_INDEX__NOTE_HASH, GENERATOR_INDEX__NOTE_NULLIFIER},
        hash::poseidon2_hash_with_separator,
        traits::{Deserialize, Hash, Packable, Serialize, ToField},
        utils::arrays::array_concat,
    },
    encrypted_logs::log_assembly_strategies::default_aes128,
};

use crate::bignum_field::BigNumField;

#[custom_note]
#[derive(Serialize)]
pub struct BigNumFieldNote {
    owner: AztecAddress,
    // Randomness of the note to hide its contents
    randomness: Field,
    // The amount of tokens in the note
    value: BigNumField,
}

impl NoteHash for BigNumFieldNote {
    fn compute_note_hash(self, storage_slot: Field) -> Field {
        // Partial notes can be implemented by having the note hash be either the result of multiscalar multiplication
        // (MSM), or two rounds of poseidon. MSM results in more constraints and is only required when multiple variants
        // of partial notes are supported. Because BigNumFieldNote has just one variant (where the value is public), we use
        // poseidon instead.

        // We must compute the same note hash as would be produced by a partial note created and completed with the same
        // values, so that notes all behave the same way regardless of how they were created. To achieve this, we
        // perform both steps of the partial note computation.

        // First we create the partial note from a commitment to the private content (including storage slot).
        let private_content =
            BigNumFieldPartialNotePrivateContent { owner: self.owner, randomness: self.randomness };
        let partial_note = PartialBigNumFieldNote {
            commitment: private_content.compute_partial_commitment(storage_slot),
        };

        // Then compute the completion note hash. In a real partial note this step would be performed in public.
        partial_note.compute_complete_note_hash(self.value)
    }

    fn compute_nullifier(
        self,
        context: &mut PrivateContext,
        note_hash_for_nullify: Field,
    ) -> Field {
        let owner_npk_m = get_public_keys(self.owner).npk_m;
        let owner_npk_m_hash = owner_npk_m.hash();
        let secret = context.request_nsk_app(owner_npk_m_hash);
        poseidon2_hash_with_separator(
            [note_hash_for_nullify, secret],
            GENERATOR_INDEX__NOTE_NULLIFIER,
        )
    }

    unconstrained fn compute_nullifier_unconstrained(self, note_hash_for_nullify: Field) -> Field {
        let owner_npk_m = get_public_keys(self.owner).npk_m;
        let owner_npk_m_hash = owner_npk_m.hash();
        let secret = get_nsk_app(owner_npk_m_hash);
        poseidon2_hash_with_separator(
            [note_hash_for_nullify, secret],
            GENERATOR_INDEX__NOTE_NULLIFIER,
        )
    }
}

impl BigNumFieldNote {
    pub fn new(value: BigNumField, owner: AztecAddress) -> Self {
        // We use the randomness to preserve the privacy of the note recipient by preventing brute-forcing, so a
        // malicious sender could use non-random values to make the note less private. But they already know the full
        // note pre-image anyway, and so the recipient already trusts them to not disclose this information. We can
        // therefore assume that the sender will cooperate in the random value generation.
        let randomness = unsafe { random() };
        Self { value: value, owner, randomness }
    }

    pub fn get_value(self) -> BigNumField {
        self.value
    }

    /// Creates a partial note that will hide the owner and storage slot but not the value, since the note will be later
    /// completed in public. This is a powerful technique for scenarios in which the value cannot be known in private
    /// (e.g. because it depends on some public state, such as a DEX).
    ///
    /// The returned `PartialBigNumFieldNote` value must be sent to public execution via a secure channel, since it is not
    /// possible to verify the integrity of its contents due to it hiding information. The recommended ways to do this
    /// are to retrieve it from public storage, or to receive it in an internal public function call.
    ///
    /// Each partial note should only be used once, since otherwise multiple notes would be linked together and known to
    /// belong to the same owner.
    ///
    /// As part of the partial note creation process, a log will be sent to `recipient` from `sender` so that they can
    /// discover the note. `recipient` will typically be the same as `owner`.
    pub fn partial(
        owner: AztecAddress,
        storage_slot: Field,
        context: &mut PrivateContext,
        recipient: AztecAddress,
        sender: AztecAddress,
    ) -> PartialBigNumFieldNote {
        // Safety: We use the randomness to preserve the privacy of the note recipient by preventing brute-forcing,
        // so a malicious sender could use non-random values to make the note less private. But they already know
        // the full note pre-image anyway, and so the recipient already trusts them to not disclose this
        // information. We can therefore assume that the sender will cooperate in the random value generation.
        let randomness = unsafe { random() };

        // We create a commitment to the private data, which we then use to construct the log we send to the recipient.
        let commitment = BigNumFieldPartialNotePrivateContent { owner, randomness }
            .compute_partial_commitment(storage_slot);

        // Our partial note log encoding scheme includes a field with the tag of the public completion log, and we use
        // the commitment as the tag. This is good for multiple reasons:
        //  - the commitment is uniquely tied to this partial note
        //  - the commitment is already public information, so we're not revealing anything else
        //  - we don't need to create any additional information, private or public, for the tag
        //  - other contracts cannot impersonate us and emit logs with the same tag due to public log siloing
        let private_log_content = PrivateBigNumFieldPartialNotePrivateLogContent {
            owner,
            randomness,
            public_log_tag: commitment,
        };

        // TODO: we're abusing the note encoding scheme by computing the log for a fake note type with such a note type
        // id that the recipient will realize that these are the private fields of a partial note. Ideally we'd not rely
        // on this crude mechanism and we'd instead compute it as a proper event log. However, given the current state
        // of the log library it's far easier to do it this way.
        let encrypted_log = default_aes128::note::compute_partial_note_log(
            private_log_content,
            storage_slot,
            recipient,
            sender,
        );
        context.emit_private_log(encrypted_log);

        PartialBigNumFieldNote { commitment }
    }
}

impl Eq for BigNumFieldNote {
    fn eq(self, other: Self) -> bool {
        (self.value == other.value)
            & (self.owner == other.owner)
            & (self.randomness == other.randomness)
    }
}

/// The private content of a partial BigNumFieldNote, i.e. the fields that will remain private. All other note fields will be
/// made public.
#[derive(Packable)]
struct BigNumFieldPartialNotePrivateContent {
    // The ordering of these fields is important given that it must match that of BigNumFieldNote.
    // Correct ordering is checked by the tests in this module.
    owner: AztecAddress,
    randomness: Field,
}

impl BigNumFieldPartialNotePrivateContent {
    fn compute_partial_commitment(self, storage_slot: Field) -> Field {
        // Here we commit to all private values, including the storage slot.
        poseidon2_hash_with_separator(
            array_concat(self.pack(), [storage_slot]),
            GENERATOR_INDEX__NOTE_HASH,
        )
    }
}

/// A partial instance of a BigNumFieldNote. This value represents a private commitment to the owner, randomness and storage
/// slot, but the value field has not yet been set. A partial note can be completed in public with the `complete`
/// function (revealing the value to the public), resulting in a BigNumFieldNote that can be used like any other one (except
/// of course that its value is known).
#[derive(Packable, Serialize, Deserialize)]
pub struct PartialBigNumFieldNote {
    commitment: Field,
}

impl PartialBigNumFieldNote {
    pub fn commitment(self) -> Field {
        self.commitment
    }
}

impl PartialBigNumFieldNote {
    /// Completes the partial note, creating a new note that can be used like any other BigNumFieldNote.
    pub fn complete(self, value: BigNumField, context: &mut PublicContext) {
        // A note with a value of zero is valid, but we cannot currently complete a partial note with such a value
        // because this will result in the completion log having its last field set to 0. Public logs currently do not
        // track their length, and so trailing zeros are simply trimmed. This results in the completion log missing its
        // last field (the value), and note discovery failing.
        // TODO(#11636): remove this
        assert(value != BigNumField::zero(), "Cannot complete a PartialBigNumFieldNote with a value of 0");

        // We need to do two things:
        //  - emit a public log containing the public fields (the value). The contract will later find it by searching
        //  for the expected tag (which is simply the partial note commitment).
        //  - insert the completion note hash (i.e. the hash of the note) into the note hash tree. This is typically
        //  only done in private to hide the preimage of the hash that is inserted, but completed partial notes are
        //  inserted in public as the public values are provided and the note hash computed.
        context.emit_public_log(self.compute_note_completion_log(value));
        context.push_note_hash(self.compute_complete_note_hash(value));
    }

    fn compute_note_completion_log(self, value: BigNumField) -> [Field; 4] {
        // The first field of this log must be the tag that the recipient of the partial note private field logs
        // expects, which is equal to the partial note commitment.
        [self.commitment, value.limbs[0] as Field, value.limbs[1] as Field, value.limbs[2] as Field]
    }

    fn compute_complete_note_hash(self, value: BigNumField) -> Field {
        // Here we finalize the note hash by including the (public) value into the partial note commitment. Note that we
        // use the same generator index as we used for the first round of poseidon - this is not an issue.
        poseidon2_hash_with_separator(
            [self.commitment, value.limbs[0] as Field, value.limbs[1] as Field, value.limbs[2] as Field],
            GENERATOR_INDEX__NOTE_HASH,
        )
    }
    // fn compute_note_completion_log(self, value: BigNumField) -> [Field; 4] {
    //     // The first field of this log must be the tag that the recipient of the partial note private field logs
    //     // expects, which is equal to the partial note commitment.
    //     [self.commitment, value.limbs[0] as Field, value.limbs[1] as Field, value.limbs[2] as Field]
    // }

    // fn compute_complete_note_hash(self, value: BigNumField) -> Field {
    //     // Here we finalize the note hash by including the (public) value into the partial note commitment. Note that we
    //     // use the same generator index as we used for the first round of poseidon - this is not an issue.
    //     poseidon2_hash_with_separator(
    //         [self.commitment, value.limbs[0] as Field, value.limbs[1] as Field, value.limbs[2] as Field],
    //         GENERATOR_INDEX__NOTE_HASH,
    //     )
    // }
}

#[derive(Packable)]
struct PrivateBigNumFieldPartialNotePrivateLogContent {
    // The ordering of these fields is important given that it must:
    //   a) match that of BigNumFieldNote, and
    //   b) have the public log tag at the beginning
    // Correct ordering is checked by the tests in this module.
    public_log_tag: Field,
    owner: AztecAddress,
    randomness: Field,
}

impl NoteType for PrivateBigNumFieldPartialNotePrivateLogContent {
    fn get_id() -> Field {
        // We abuse the fact that note type ids are 7 bits long to use the 8th bit indicate the log corresponds to a
        // partial note. Ideally we'd use proper events with selectors, but those are not handled well at the moment.
        BigNumFieldNote::get_id() + 128
    }
}