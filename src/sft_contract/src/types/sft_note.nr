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

use crate::types::nft_note::{NFTPartialNotePrivateContent, PartialNFTNote};

/// A private note representing a specific amount of a specific token ID owned by an account.
/// @dev Similar to NFTNote but with an additional amount field for tracking quantities
#[custom_note]
#[derive(Eq, Serialize)]
pub struct SFTNote {
    // The ordering of these fields is important for serialization
    owner: AztecAddress,
    randomness: Field,
    token_id: Field,
    amount: u128,  // New field for tracking token amounts
}

#[derive(Packable)]
struct PrivateSFTPartialNotePrivateLogContent {
    public_log_tag: Field,
    owner: AztecAddress,
    randomness: Field,
}

impl NoteType for PrivateSFTPartialNotePrivateLogContent {
    fn get_id() -> Field {
        // Follow the same pattern as NFT - use 8th bit to indicate partial note log
        SFTNote::get_id() + 128
    }
}

impl NoteHash for SFTNote {
    /// Computes the hash of this note for a given storage slot
    fn compute_note_hash(self, storage_slot: Field) -> Field {
        // Hash all note fields together with the storage slot
        poseidon2_hash_with_separator(
            array_concat(self.pack(), [storage_slot]),
            GENERATOR_INDEX__NOTE_HASH,
        )
    }

    /// Computes the nullifier for this note using the provided note hash
    /// @dev The nullifier is used to prevent double-spending of notes
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

    /// Unconstrained version of compute_nullifier for use in view functions
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
    /// Creates a new SFT note
    pub fn new(token_id: Field, amount: u128, owner: AztecAddress) -> Self {
        // Safety: random is safe here as it's only used for note initialization
        let randomness = unsafe { random() };
        Self { token_id, amount, owner, randomness }
    }

    pub fn get_token_id(self) -> Field {
        self.token_id
    }

    pub fn get_amount(self) -> u128 {
        self.amount
    }

    /// Creates a partial note for privacy-preserving transfers
    pub fn partial(
        owner: AztecAddress,
        storage_slot: Field,
        context: &mut PrivateContext,
        recipient: AztecAddress,
        sender: AztecAddress,
    ) -> PartialSFTNote {
        // Safety: random is safe here as it's only used for note initialization
        let randomness = unsafe { random() };

        // Create commitment to private data using NFT's private content structure
        let commitment = NFTPartialNotePrivateContent { owner, randomness }
            .compute_partial_commitment(storage_slot);

        // Create and return partial note
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

    /// Completes the partial note by adding token_id and amount
    pub fn complete(self, token_id: Field, amount: u128, context: &mut PublicContext) {
        // Ensure non-zero amount
        assert(amount != 0, "Cannot complete a PartialSFTNote with amount of 0");

        // Emit public log and insert note hash
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
