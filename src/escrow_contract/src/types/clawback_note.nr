use aztec::{
    context::PrivateContext,
    keys::getters::{get_nsk_app, get_public_keys},
    macros::notes::custom_note,
    note::note_interface::NoteHash,
    oracle::random::random,
    protocol_types::{
        address::AztecAddress,
        constants::{GENERATOR_INDEX__NOTE_HASH, GENERATOR_INDEX__NOTE_NULLIFIER},
        hash::poseidon2_hash_with_separator,
        traits::{Hash, Serialize, ToField},
    },
};

/// @notice A private note representing a clawback escrow configuration
/// @dev Contains all information needed for a clawback escrow implementation
#[custom_note]
#[derive(Eq, Serialize)]
pub struct ClawbackNote {
    /// The address of the escrow contract
    escrow: AztecAddress,
    /// The address that can receive the tokens upon release
    recipient: AztecAddress,
    /// The address that has ownership rights over the escrow
    owner: AztecAddress,
    /// The address of the token contract
    token: AztecAddress,
    /// The amount of tokens in the escrow
    amount: u128,
    /// The deadline timestamp after which recipient can claim
    deadline: u64,
    /// Random value for privacy protection
    randomness: Field,
}

impl NoteHash for ClawbackNote {
    fn compute_note_hash(self, storage_slot: Field) -> Field {
        // Create a hash of all the note's fields along with the storage slot
        let serialized = [
            self.escrow.to_field(),
            self.recipient.to_field(), 
            self.owner.to_field(),
            self.token.to_field(),
            self.amount as Field,
            self.deadline as Field,
            self.randomness,
            storage_slot,
        ];
        
        poseidon2_hash_with_separator(serialized, GENERATOR_INDEX__NOTE_HASH)
    }

    fn compute_nullifier(
        self,
        context: &mut PrivateContext,
        note_hash_for_nullify: Field,
    ) -> Field {
        // Use the owner's nullifier secret key to compute the nullifier
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

impl ClawbackNote {
    /// @notice Creates a new ClawbackNote
    /// @param escrow The address of the escrow contract
    /// @param recipient The address that can receive the tokens
    /// @param owner The address that has ownership rights
    /// @param token The address of the token contract
    /// @param amount The amount of tokens in the escrow
    /// @param deadline The deadline timestamp
    pub fn new(
        escrow: AztecAddress,
        recipient: AztecAddress,
        owner: AztecAddress,
        token: AztecAddress,
        amount: u128,
        deadline: u64,
    ) -> Self {
        // Safety: We use the randomness to preserve the privacy of the note recipient by preventing brute-forcing,
        // so a malicious sender could use non-random values to make the note less private. But they already know
        // the full note pre-image anyway, and so the recipient already trusts them to not disclose this
        // information. We can therefore assume that the sender will cooperate in the random value generation.
        let randomness = unsafe { random() };
        Self {
            escrow,
            recipient,
            owner,
            token,
            amount,
            deadline,
            randomness,
        }
    }

    /// @notice Returns the escrow address
    pub fn get_escrow(self) -> AztecAddress {
        self.escrow
    }

    /// @notice Returns the recipient address
    pub fn get_recipient(self) -> AztecAddress {
        self.recipient
    }

    /// @notice Returns the owner address
    pub fn get_owner(self) -> AztecAddress {
        self.owner
    }

    /// @notice Returns the token address
    pub fn get_token(self) -> AztecAddress {
        self.token
    }

    /// @notice Returns the amount of tokens
    pub fn get_amount(self) -> u128 {
        self.amount
    }

    /// @notice Returns the deadline timestamp
    pub fn get_deadline(self) -> u64 {
        self.deadline
    }

    /// @notice Returns the randomness value
    pub fn get_randomness(self) -> Field {
        self.randomness
    }
}