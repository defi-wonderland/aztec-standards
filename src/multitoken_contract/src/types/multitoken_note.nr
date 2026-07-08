use aztec::{
    context::{NullifierExistenceRequest, PrivateContext, PublicContext},
    keys::getters::{get_nhk_app, get_public_keys, try_get_public_keys},
    macros::notes::custom_note,
    messages::{
        delivery::{do_private_message_delivery, MessageDelivery},
        logs::partial_note::encode_partial_note_private_message,
    },
    note::{
        note_interface::{NoteHash, NoteType},
        utils::{compute_note_hash, compute_note_nullifier},
    },
    oracle::random::random,
    protocol::{
        address::AztecAddress,
        constants::{
            DOM_SEP__NOTE_COMPLETION_LOG_TAG, DOM_SEP__PARTIAL_NOTE_COMMITMENT,
            DOM_SEP__PARTIAL_NOTE_VALIDITY_COMMITMENT,
        },
        hash::{compute_log_tag, compute_siloed_nullifier, poseidon2_hash_with_separator},
        traits::{Deserialize, FromField, Packable, Serialize, ToField},
    },
};

// MultiTokenNote supports partial notes, i.e. the ability to create an incomplete note in private, hiding certain
// values (the owner, storage slot and randomness), and then completing the note in public with the ones missing (the
// token id and value). Partial notes are being actively developed and are not currently fully supported via macros,
// and so we rely on the #[custom_note] macro to implement it manually, resulting in some boilerplate. This is expected
// to be unnecessary once macro support is expanded.
//
// Unlike UintNote (one public completion field: value) or NFTNote (one public completion field: token id), a
// MultiTokenNote has TWO public completion fields: token_id and value. Both are chained into the completion note hash
// and the completion log, in that order. Because this is still a single partial-note variant (multiple public fields,
// not multiple variants), the note hash is a plain Poseidon chain with no multi-scalar-multiplication.

/// A private note representing an amount of a specific token id associated to an account.
// Deserialize is derived (in addition to the nft_note trait set) because this note is used with a min-sum preprocessor
// over `HintedNote<MultiTokenNote>`, matching the UintNote trait set used by balance_set.
#[derive(Deserialize, Eq, Serialize, Packable)]
#[custom_note]
pub struct MultiTokenNote {
    /// The id of the token represented by this note.
    pub token_id: Field,
    /// The fungible amount of `token_id` stored in the note.
    pub value: u128,
}

impl NoteHash for MultiTokenNote {
    fn compute_note_hash(
        self,
        owner: AztecAddress,
        storage_slot: Field,
        randomness: Field,
    ) -> Field {
        // Partial notes can be implemented by having the note hash be either the result of multiscalar multiplication
        // (MSM), or two rounds of poseidon. MSM results in more constraints and is only required when multiple variants
        // of partial notes are supported. Because MultiTokenNote has just one variant (where the token id and value are
        // public), we use poseidon instead.

        // We must compute the same note hash as would be produced by a partial note created and completed with the same
        // values, so that notes all behave the same way regardless of how they were created. To achieve this, we
        // perform both steps of the partial note computation.

        // First we create the partial note from a commitment to the private content.
        let partial_note =
            PartialMultiTokenNote { commitment: compute_partial_commitment(owner, randomness) };

        // Then compute the completion note hash. In a real partial note this step would be performed in public.
        partial_note.compute_complete_note_hash(storage_slot, self.token_id, self.value)
    }

    // The nullifiers are nothing special - this is just the canonical implementation that would be injected by the
    // #[note] macro.

    fn compute_nullifier(
        self,
        context: &mut PrivateContext,
        owner: AztecAddress,
        note_hash_for_nullification: Field,
    ) -> Field {
        let owner_npk_m_hash = get_public_keys(owner).npk_m_hash;
        let secret = context.request_nhk_app(owner_npk_m_hash);
        compute_note_nullifier(note_hash_for_nullification, [secret])
    }

    unconstrained fn compute_nullifier_unconstrained(
        self,
        owner: AztecAddress,
        note_hash_for_nullification: Field,
    ) -> Option<Field> {
        try_get_public_keys(owner).map(|public_keys| {
            let owner_npk_m_hash = public_keys.npk_m_hash;
            let secret = get_nhk_app(owner_npk_m_hash);
            compute_note_nullifier(note_hash_for_nullification, [secret])
        })
    }
}

impl MultiTokenNote {
    /// Creates a partial note that will hide the owner and storage slot but not the token id and value, since the note
    /// will be later completed in public. This is a powerful technique for scenarios in which the token id or value
    /// cannot be known in private (e.g. because they depend on some public state).
    ///
    /// This function inserts a partial note validity commitment into the nullifier tree to be later on able to verify
    /// that the partial note and completer are legitimate. See function docs of `compute_validity_commitment` for more
    /// details.
    ///
    /// Each partial note should only be used once, since otherwise multiple notes would be linked together and known to
    /// belong to the same owner.
    ///
    /// As part of the partial note creation process, a log will be sent to `recipient` so that they can discover the
    /// note. `recipient` will typically be the same as `owner`.
    pub fn partial(
        owner: AztecAddress,
        context: &mut PrivateContext,
        recipient: AztecAddress,
        completer: AztecAddress,
    ) -> PartialMultiTokenNote {
        // Safety: We use the randomness to preserve the privacy of the note recipient by preventing brute-forcing, so a
        // malicious sender could use non-random values to make the note less private. But they already know the full
        // note pre-image anyway, and so the recipient already trusts them to not disclose this information. We can
        // therefore assume that the sender will cooperate in the random value generation.
        let randomness = unsafe { random() };

        // We create a commitment to the private data, which we then use to construct the log we send to the recipient.
        let commitment = compute_partial_commitment(owner, randomness);

        // Our partial note log encoding scheme includes a field with the tag of the public completion log, and we use
        // the commitment as the tag. This is good for multiple reasons:
        //  - the commitment is uniquely tied to this partial note
        //  - the commitment is already public information, so we're not revealing anything else
        //  - we don't need to create any additional information, private or public, for the tag
        //  - other contracts cannot impersonate us and emit logs with the same tag due to public log siloing
        let private_log_content = MultiTokenPartialNotePrivateLogContent {};

        do_private_message_delivery(
            context,
            || {
                encode_partial_note_private_message(
                    private_log_content,
                    owner,
                    randomness,
                    commitment,
                )
            },
            Option::none(),
            recipient,
            MessageDelivery::onchain_unconstrained(),
        );

        let partial_note = PartialMultiTokenNote { commitment };

        // Now we compute the validity commitment and push it to the nullifier tree. It can be safely pushed to the
        // nullifier tree since it uses its own separator, making collisions with actual note nullifiers practically
        // impossible.
        let validity_commitment = partial_note.compute_validity_commitment(completer);
        context.push_nullifier_unsafe(validity_commitment);

        partial_note
    }
}

/// Computes a commitment to the private content of a partial MultiTokenNote, i.e. the fields that will remain private
/// (the owner and randomness). All other note fields (storage slot, token id and value) will be made public.
fn compute_partial_commitment(owner: AztecAddress, randomness: Field) -> Field {
    poseidon2_hash_with_separator(
        [owner.to_field(), randomness],
        DOM_SEP__PARTIAL_NOTE_COMMITMENT,
    )
}

#[derive(Packable)]
// This note does not have any non-metadata (i.e. storage slot, owner, randomness) private content, as both fields
// (token_id and value) will be public in the partial note.
struct MultiTokenPartialNotePrivateLogContent {}

impl NoteType for MultiTokenPartialNotePrivateLogContent {
    fn get_id() -> Field {
        MultiTokenNote::get_id()
    }
}

/// A partial instance of a MultiTokenNote. This value represents a private commitment to the owner, randomness and
/// storage slot, but the token id and value fields have not yet been set. A partial note can be completed in public
/// with the `complete` function (revealing the token id and value to the public), resulting in a MultiTokenNote that
/// can be used like any other one.
#[derive(Packable, Serialize, Deserialize, Eq)]
pub struct PartialMultiTokenNote {
    pub commitment: Field,
}

impl PartialMultiTokenNote {
    /// Completes the partial note, creating a new note that can be used like any other MultiTokenNote.
    pub fn complete(
        self,
        context: PublicContext,
        completer: AztecAddress,
        storage_slot: Field,
        token_id: Field,
        value: u128,
    ) {
        // A note with a value of zero is valid, but we cannot currently complete a partial note with such a value
        // because this will result in the completion log having its last field set to 0. Public logs currently do not
        // track their length, and so trailing zeros are simply trimmed. This results in the completion log missing its
        // last field (the value), and note discovery failing. TODO(#11636): remove this
        //
        // The guard is on `value` (the LAST chained public field), NOT on `token_id`, so that `id = 0` remains a valid,
        // completable token id.
        assert(value != 0, "Cannot complete a PartialMultiTokenNote with a value of 0");

        // We verify that the partial note we're completing is valid (i.e. completer is correct, it uses the correct
        // state variable's storage slot, and it is internally consistent).
        let validity_commitment = self.compute_validity_commitment(completer);
        // Safety: we're using the existence of the nullifier as proof of the contract having validated the partial
        // note's preimage, which is safe.
        assert(
            context.nullifier_exists_unsafe(validity_commitment, context.this_address()),
            "Invalid partial note or completer",
        );

        // We need to do two things:
        //  - emit a public log containing the public fields (the storage slot, token id and value). The contract will
        //  later find it by searching for the domain-separated commitment as the tag.
        //  - insert the completion note hash (i.e. the hash of the note) into the note hash tree. This is typically
        //  only done in private to hide the preimage of the hash that is inserted, but completed partial notes are
        //  inserted in public as the public values are provided and the note hash computed.
        let log_tag = compute_log_tag(self.commitment, DOM_SEP__NOTE_COMPLETION_LOG_TAG);
        context.emit_public_log_unsafe(log_tag, [storage_slot, token_id, value.to_field()]);
        context.push_note_hash(self.compute_complete_note_hash(storage_slot, token_id, value));
    }

    /// Completes the partial note, creating a new note that can be used like any other MultiTokenNote. Same as
    /// `complete` but works from private context, requiring the validity commitment to have been created in a prior
    /// settled transaction.
    pub fn complete_from_private(
        self,
        context: &mut PrivateContext,
        completer: AztecAddress,
        storage_slot: Field,
        token_id: Field,
        value: u128,
    ) {
        // We verify that the partial note we're completing is valid (i.e. completer is correct, it uses the correct
        // state variable's storage slot, and it is internally consistent).
        let validity_commitment = self.compute_validity_commitment(completer);

        let siloed_validity_commitment =
            compute_siloed_nullifier(context.this_address(), validity_commitment);
        // Note that this means we don't support scenarios in which the validity commitment was created in the same
        // transaction.
        context.assert_nullifier_exists(NullifierExistenceRequest::for_settled(
            siloed_validity_commitment,
        ));

        // We need to do two things:
        //  - emit an unencrypted log containing the public fields (the storage slot, token id and value) via the
        //  private log channel. The contract will later find it by searching for the domain-separated commitment as the
        //  tag.
        //  - insert the completion note hash (i.e. the hash of the note) into the note hash tree. This is typically
        //  only done in private to hide the preimage of the hash that is inserted, but completed partial notes are
        //  inserted in public as the public values are provided and the note hash computed.
        let log_tag = compute_log_tag(self.commitment, DOM_SEP__NOTE_COMPLETION_LOG_TAG);
        let payload = BoundedVec::from_array([storage_slot, token_id, value.to_field()]);
        context.emit_private_log_unsafe(log_tag, payload);
        context.push_note_hash(self.compute_complete_note_hash(storage_slot, token_id, value));
    }

    /// Computes a validity commitment for this partial note. The commitment cryptographically binds the note's private
    /// data with the designated completer address. When the note is later completed in public execution, we can load
    /// this commitment from the nullifier tree and verify that both the partial note (e.g. that the storage slot
    /// corresponds to the correct owner, and that we're using the correct state variable) and completer are legitimate.
    pub fn compute_validity_commitment(self, completer: AztecAddress) -> Field {
        poseidon2_hash_with_separator(
            [self.commitment, completer.to_field()],
            DOM_SEP__PARTIAL_NOTE_VALIDITY_COMMITMENT,
        )
    }

    fn compute_complete_note_hash(
        self,
        storage_slot: Field,
        token_id: Field,
        value: u128,
    ) -> Field {
        // Finalize the note hash by folding the (public) storage slot, token id and value into the partial note
        // commitment. `compute_note_hash` fixes the storage slot at the first position of the preimage (preventing
        // cross-slot collisions) and appends the remaining fields in order.
        compute_note_hash(storage_slot, [self.commitment, token_id, value.to_field()])
    }
}

impl ToField for PartialMultiTokenNote {
    fn to_field(self) -> Field {
        self.commitment
    }
}

impl FromField for PartialMultiTokenNote {
    fn from_field(field: Field) -> Self {
        Self { commitment: field }
    }
}
