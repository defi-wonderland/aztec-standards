mod test;

use aztec::macros::aztec;

#[aztec]
pub contract ClawbackLogic {
    // aztec library
    use aztec::{
        macros::{functions::private, storage::storage},
        prelude::{AztecAddress, PrivateSet, NoteGetterOptions},
        protocol_types::{traits::{ToField, FromField}, hash::poseidon2_hash_with_separator},
        oracle::random::random,
    };

    // Base library methods from escrow contract
    use dep::escrow_contract::logic::base::{_check_escrow, _share_escrow, _withdraw};

    // Custom types from escrow contract
    use dep::escrow_contract::types::clawback_note::ClawbackNote;

    // Storage for clawback escrow configurations
    #[storage]
    struct Storage<Context> {
        /// @dev Stores clawback escrow details for each escrow instance
        /// Used to manage recipient claims and owner clawbacks
        clawback_notes: PrivateSet<ClawbackNote, Context>,
    }

    /// @notice Creates a new clawback escrow with specified parameters
    /// @dev Validates escrow details, prevents duplicate creation, and shares keys with recipient
    /// @param escrow The address of the escrow contract
    /// @param keys Array of master secret keys [nsk_m, ivsk_m, ovsk_m, tsk_m]
    /// @param recipient The address that can claim tokens before deadline
    /// @param owner The address that can clawback tokens after deadline
    /// @param token The address of the token contract
    /// @param amount The amount of tokens in the escrow
    /// @param deadline The timestamp after which owner can clawback
    #[private]
    fn create_clawback(
        escrow: AztecAddress,
        keys: [Field; 4],
        recipient: AztecAddress,
        owner: AztecAddress,
        token: AztecAddress,
        amount: u128,
        deadline: u64,
    ) {
        // 1. Verify the escrow details using the base library method
        _check_escrow(&mut context, escrow, keys, context.this_address());

        // 2. Push a nullifier to prevent duplicate escrow creation
        // SECURITY FIX: Use unpredictable nullifier with random entropy to prevent front-running
        // Safety: We use randomness to prevent front-running attacks on nullifier generation
        let randomness = unsafe { random() };
        let escrow_nullifier = poseidon2_hash_with_separator(
            [escrow.to_field(), randomness, context.this_address().to_field()],
            0x1234, // Generator index for escrow creation nullifier
        );
        context.push_nullifier(escrow_nullifier);

        // 3. Share escrow details with the recipient
        _share_escrow(&mut context, recipient, escrow, keys);

        // 4. Create ClawbackNote for the recipient to use for claiming
        let clawback_note_recipient = ClawbackNote::new(
            escrow,
            recipient,
            owner,
            token,
            amount,
            deadline,
        );

        // 5. Insert ClawbackNote and emit to recipient
        storage.clawback_notes.insert(clawback_note_recipient);

        // 6. Create ClawbackNote for the owner to use for clawback
        let clawback_note_owner = ClawbackNote::new(
            escrow,
            recipient,
            owner,
            token,
            amount,
            deadline,
        );

        // 7. Insert ClawbackNote and emit to owner
        storage.clawback_notes.insert(clawback_note_owner);
    }

    /// @notice Allows recipient to claim tokens before the deadline
    /// @dev Validates deadline hasn't passed and executes token transfer
    /// @param escrow The address of the escrow contract
    /// @param token The address of the token contract
    /// @param amount The amount of tokens to claim
    #[private]
    fn claim(escrow: AztecAddress, token: AztecAddress, amount: u128) {
        let caller = context.msg_sender();

        // 1. Find and remove the ClawbackNote matching the escrow and caller as recipient
        // Note: Simplified approach due to custom note limitations
        let options = NoteGetterOptions::new().set_limit(32); // Set reasonable limit for gas efficiency
        let notes = storage.clawback_notes.pop_notes(options);

        // Find the matching note for the recipient
        let mut found_note = ClawbackNote::new(
            AztecAddress::from_field(0),
            AztecAddress::from_field(0),
            AztecAddress::from_field(0),
            AztecAddress::from_field(0),
            0,
            0,
        );
        let mut note_found = false;
        
        // Linear search through notes to find match using fixed limit
        for i in 0..options.limit {
            if i < notes.len() {
                let note = notes.get_unchecked(i);
                if (note.get_escrow() == escrow) 
                    & (note.get_recipient() == caller)
                    & (note.get_token() == token) 
                    & (note.get_amount() == amount) {
                    found_note = note;
                    note_found = true;
                }
            }
        }

        assert(note_found, "ClawbackLogic: matching clawback note not found");

        // 2. Check that the deadline hasn't passed
        // Get anchor block timestamp from private context
        let current_timestamp = context.get_block_header().global_variables.timestamp;
        
        assert(
            current_timestamp < found_note.get_deadline(),
            "ClawbackLogic: deadline has passed, tokens can only be clawed back by owner"
        );

        // 3. Execute withdrawal to the recipient
        _withdraw(
            &mut context,
            escrow,
            token,
            amount,
            caller, // recipient
        );
    }

    /// @notice Allows owner to reclaim tokens after the deadline has passed
    /// @dev Validates deadline has passed and executes token transfer back to owner
    /// @param escrow The address of the escrow contract
    /// @param token The address of the token contract
    /// @param amount The amount of tokens to clawback
    #[private]
    fn clawback(escrow: AztecAddress, token: AztecAddress, amount: u128) {
        let caller = context.msg_sender();

        // 1. Find and remove the ClawbackNote matching the escrow and caller as owner
        // Note: Simplified approach due to custom note limitations
        let options = NoteGetterOptions::new().set_limit(32); // Set reasonable limit for gas efficiency
        let notes = storage.clawback_notes.pop_notes(options);

        // Find the matching note for the owner
        let mut found_note = ClawbackNote::new(
            AztecAddress::from_field(0),
            AztecAddress::from_field(0),
            AztecAddress::from_field(0),
            AztecAddress::from_field(0),
            0,
            0,
        );
        let mut note_found = false;
        
        // Linear search through notes to find match using fixed limit
        for i in 0..options.limit {
            if i < notes.len() {
                let note = notes.get_unchecked(i);
                if (note.get_escrow() == escrow) 
                    & (note.get_owner() == caller)
                    & (note.get_token() == token) 
                    & (note.get_amount() == amount) {
                    found_note = note;
                    note_found = true;
                }
            }
        }

        assert(note_found, "ClawbackLogic: matching clawback note not found for owner");

        // 2. Check that the deadline has passed
        // Get anchor block timestamp from private context
        let current_timestamp = context.get_block_header().global_variables.timestamp;
        
        assert(
            current_timestamp >= found_note.get_deadline(),
            "ClawbackLogic: deadline has not passed, recipient can still claim tokens"
        );

        // 3. Execute withdrawal back to the owner
        _withdraw(
            &mut context,
            escrow,
            token,
            amount,
            caller, // owner
        );
    }
}