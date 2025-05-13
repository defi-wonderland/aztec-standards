use dep::aztec::{
    context::{PrivateContext, PublicContext},
    keys::getters::{get_nsk_app, get_public_keys},
    macros::notes::custom_note,
    note::note_interface::{NoteHash, NoteType},
    oracle::random::random,
    protocol_types::{
        address::AztecAddress,
        constants::{GENERATOR_INDEX__NOTE_HASH, GENERATOR_INDEX__NOTE_NULLIFIER},
        hash::poseidon2_hash_with_separator,
        traits::{Deserialize, Hash, Packable, Serialize},
        utils::arrays::array_concat,
    },
};

/// A private note representing a specific amount of a specific token ID owned by an account.
#[custom_note]
#[derive(Eq, Serialize)]
pub struct SFTNote {
    // The ordering of these fields is important for serialization
    owner: AztecAddress,
    randomness: Field,
    token_id: Field,
    amount: u128,  // Field for tracking token amounts
}

/// Private content structure for partial notes
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
        // Use 8th bit to indicate partial note log
        SFTNote::get_id() + 128
    }
}

impl NoteHash for SFTNote {
    fn compute_note_hash(self, storage_slot: Field) -> Field {
        poseidon2_hash_with_separator(
            array_concat(self.pack(), [storage_slot]),
            GENERATOR_INDEX__NOTE_HASH,
        )
    }

    fn compute_nullifier(self, context: &mut PrivateContext, note_hash_for_nullify: Field) -> Field {
        // Safety: get_public_keys is safe here as we're only accessing public key data
        let owner_npk_m = unsafe { get_public_keys(self.owner).npk_m };
        let owner_npk_m_hash = owner_npk_m.hash();
        // Safety: get_nsk_app is safe as we're in a private context with proper authorization
        let secret = unsafe { get_nsk_app(owner_npk_m_hash) };

        // Compute nullifier using the note hash and secret
        poseidon2_hash_with_separator(
            [note_hash_for_nullify, secret],
            GENERATOR_INDEX__NOTE_NULLIFIER,
        )
    }

    unconstrained fn compute_nullifier_unconstrained(self, note_hash_for_nullify: Field) -> Field {
        // Safety: get_public_keys is safe in unconstrained context for view operations
        let owner_npk_m = unsafe { get_public_keys(self.owner).npk_m };
        let owner_npk_m_hash = owner_npk_m.hash();
        // Safety: get_nsk_app is safe in unconstrained context for view operations
        let secret = unsafe { get_nsk_app(owner_npk_m_hash) };
        poseidon2_hash_with_separator(
            [note_hash_for_nullify, secret],
            GENERATOR_INDEX__NOTE_NULLIFIER,
        )
    }
}

impl SFTNote {
    pub fn new(token_id: Field, amount: u128, owner: AztecAddress) -> Self {
        let randomness = unsafe { random() };
        Self { token_id, amount, owner, randomness }
    }

    pub fn get_token_id(self) -> Field {
        self.token_id
    }

    pub fn get_amount(self) -> u128 {
        self.amount
    }

    pub fn partial(
        owner: AztecAddress,
        storage_slot: Field,
        context: &mut PrivateContext,
        recipient: AztecAddress,
        sender: AztecAddress,
    ) -> PartialSFTNote {
        let randomness = unsafe { random() };

        // Create commitment to private data
        let commitment = SFTPartialNotePrivateContent { owner, randomness }
            .compute_partial_commitment(storage_slot);

        // Create and emit private log
        let private_log_content = PrivateSFTPartialNotePrivateLogContent {
            owner,
            randomness,
            public_log_tag: commitment,
        };

        // Get note type ID and pack content
        let note_type_id = PrivateSFTPartialNotePrivateLogContent::get_id();
        let packed_content = private_log_content.pack();

        // Create and emit log
        let mut log = [0; 18];
        log[0] = note_type_id;
        for i in 0..packed_content.len() {
            log[i + 1] = packed_content[i];
        }
        context.emit_private_log(log);

        PartialSFTNote { commitment }
    }
}

/// A partial note used for privacy-preserving transfers of SFTs
#[derive(Packable, Serialize, Deserialize)]
pub struct PartialSFTNote {
    commitment: Field,
}

impl PartialSFTNote {
    pub fn commitment(self) -> Field {
        self.commitment
    }

    pub fn complete(self, token_id: Field, amount: u128, context: &mut PublicContext) {
        assert(amount != 0, "Cannot complete a PartialSFTNote with amount of 0");

        context.emit_public_log(self.compute_note_completion_log(token_id, amount));
        context.push_note_hash(self.compute_complete_note_hash(token_id, amount));
    }

    fn compute_note_completion_log(self, token_id: Field, amount: u128) -> [Field; 3] {
        [self.commitment, token_id, Field::from(amount)]
    }

    fn compute_complete_note_hash(self, token_id: Field, amount: u128) -> Field {
        poseidon2_hash_with_separator(
            [self.commitment, token_id, Field::from(amount)],
            GENERATOR_INDEX__NOTE_HASH
        )
    }
}
