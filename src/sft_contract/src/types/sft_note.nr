use aztec::{
    context::{PrivateContext, PublicContext},
    keys::getters::{get_nsk_app, get_public_keys},
    macros::notes::custom_note,
    messages::logs::note,
    note::note_interface::{NoteHash, NoteType},
    oracle::random::random,
    protocol_types::{
        address::AztecAddress,
        constants::{
            GENERATOR_INDEX__NOTE_HASH, GENERATOR_INDEX__NOTE_NULLIFIER,
            GENERATOR_INDEX__PARTIAL_NOTE_VALIDITY_COMMITMENT,
        },
        hash::poseidon2_hash_with_separator,
        traits::{Deserialize, Hash, Packable, Serialize, ToField},
        utils::arrays::array_concat,
    },
};

// SFTNote supports partial notes for privacy-preserving completion in public contexts.
// Each SFTNote represents exactly 1 item with both token_id (type) and item_id (unique instance).
// Items are whole, indivisible units that cannot be fractionalized.

/// A private note representing a single item of a specific token type owned by an account.
#[custom_note]
#[derive(Eq, Serialize)]
pub struct SFTNote {
    // The ordering of these fields is important given that it must:
    //   a) match that of SFTPartialNotePrivateContent, and
    //   b) have the public fields at the end
    // Correct ordering is checked by the tests in this module.

    /// The owner of the note, i.e. the account whose nullifier secret key is required to compute the nullifier.
    owner: AztecAddress,
    /// Random value, protects against note hash preimage attacks.
    randomness: Field,
    /// The ID of the token type represented by this note.
    token_id: Field,
    /// The unique item ID within the token type. Each SFTNote represents exactly 1 item.
    item_id: Field,
}

impl NoteHash for SFTNote {
    fn compute_note_hash(self, storage_slot: Field) -> Field {
        // Similar to NFTNote, we use poseidon for partial note compatibility
        // We must compute the same note hash as would be produced by a partial note

        // First we create the partial note from a commitment to the private content
        let private_content =
            SFTPartialNotePrivateContent { owner: self.owner, randomness: self.randomness };
        let partial_note =
            PartialSFTNote { commitment: private_content.compute_partial_commitment(storage_slot) };

        // Then compute the completion note hash. In a real partial note this step would be performed in public.
        partial_note.compute_complete_note_hash(self.token_id, self.item_id)
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

impl SFTNote {
    /// Creates a new SFTNote with the specified token_id, item_id, and owner.
    /// @param token_id The ID of the token type
    /// @param item_id The unique item ID within the token type
    /// @param owner The owner of the tokens
    pub fn new(token_id: Field, item_id: Field, owner: AztecAddress) -> Self {
        // Safe: randomness is used to prevent note hash preimage attacks
        let randomness = unsafe { random() };
        Self { token_id, item_id, owner, randomness }
    }

    pub fn get_token_id(self) -> Field {
        self.token_id
    }

    pub fn get_item_id(self) -> Field {
        self.item_id
    }

    /// Creates a partial note that will hide the owner and storage slot but not the token_id and item_id.
    /// This enables privacy-preserving transfers where token details are completed in public.
    pub fn partial(
        owner: AztecAddress,
        storage_slot: Field,
        context: &mut PrivateContext,
        recipient: AztecAddress,
        sender: AztecAddress,
        completer: AztecAddress,
    ) -> PartialSFTNote {
        // Safe: randomness is used to prevent note hash preimage attacks
        let randomness = unsafe { random() };

        let commitment = SFTPartialNotePrivateContent { owner, randomness }
            .compute_partial_commitment(storage_slot);

        let private_log_content = PrivateSFTPartialNotePrivateLogContent {
            owner,
            randomness,
            public_log_tag: commitment,
        };

        let encrypted_log =
            note::compute_partial_note_log(private_log_content, storage_slot, recipient, sender);
        let length = encrypted_log.len();
        context.emit_private_log(encrypted_log, length);

        let partial_note = PartialSFTNote { commitment };

        let validity_commitment = partial_note.compute_validity_commitment(completer);
        context.push_nullifier(validity_commitment);

        partial_note
    }
}

/// The private content of a partial SFTNote - fields that remain private
#[derive(Packable)]
struct SFTPartialNotePrivateContent {
    owner: AztecAddress,
    randomness: Field,
}

impl SFTPartialNotePrivateContent {
    fn compute_partial_commitment(self, storage_slot: Field) -> Field {
        poseidon2_hash_with_separator(
            array_concat(self.pack(), [storage_slot]),
            GENERATOR_INDEX__NOTE_HASH,
        )
    }
}

#[derive(Packable)]
struct PrivateSFTPartialNotePrivateLogContent {
    public_log_tag: Field,
    owner: AztecAddress,
    randomness: Field,
}

impl NoteType for PrivateSFTPartialNotePrivateLogContent {
    fn get_id() -> Field {
        SFTNote::get_id()
    }
}

/// A partial instance of a SFTNote. This represents a commitment to owner/randomness/storage_slot,
/// but token_id and item_id fields are set later in public.
#[derive(Packable, Serialize, Deserialize)]
pub struct PartialSFTNote {
    commitment: Field,
}

impl PartialSFTNote {
    pub fn commitment(self) -> Field {
        self.commitment
    }

    /// Completes the partial note, creating a new note that can be used like any other SFTNote.
    /// @param context The public context for completion
    /// @param completer The address completing the note
    /// @param token_id The token ID to complete with
    /// @param item_id The unique item ID to complete with
    pub fn complete(
        self,
        context: &mut PublicContext,
        completer: AztecAddress,
        token_id: Field,
        item_id: Field,
    ) {
        assert(token_id != 0, "Cannot complete a PartialSFTNote with a token_id of 0");

        let validity_commitment = self.compute_validity_commitment(completer);
        assert(
            context.nullifier_exists(validity_commitment, context.this_address()),
            "Invalid partial note or completer",
        );

        context.emit_public_log(self.compute_note_completion_log(token_id, item_id));
        context.push_note_hash(self.compute_complete_note_hash(token_id, item_id));
    }

    pub fn compute_validity_commitment(self, completer: AztecAddress) -> Field {
        poseidon2_hash_with_separator(
            [self.commitment, completer.to_field()],
            GENERATOR_INDEX__PARTIAL_NOTE_VALIDITY_COMMITMENT,
        )
    }

    fn compute_note_completion_log(self, token_id: Field, item_id: Field) -> [Field; 3] {
        [self.commitment, token_id, item_id]
    }

    fn compute_complete_note_hash(self, token_id: Field, item_id: Field) -> Field {
        poseidon2_hash_with_separator(
            [self.commitment, token_id, item_id],
            GENERATOR_INDEX__NOTE_HASH,
        )
    }
}
