mod types;
mod test;

use aztec::macros::aztec;

#[aztec]
pub contract SFT {
    // Import necessary modules and types
    use crate::types::sft_note::{SFTNote, PartialSFTNote}; 
    
    // aztec library imports
    use aztec::{
        context::PrivateContext,
        macros::{
            functions::{initializer, internal, private, public, utility, view},
            storage::storage,
        },
        messages::logs::note::encode_and_encrypt_note,
        note::{constants::MAX_NOTES_PER_PAGE, note_interface::NoteProperties},
        prelude::{
            AztecAddress, Map, NoteGetterOptions, NoteViewerOptions, 
            PrivateSet, PublicContext, PublicImmutable, PublicMutable,
        },
        utils::comparison::Comparator,
    };
    
    // authorized witness library
    use authwit::auth::{
        assert_current_call_valid_authwit,
        assert_current_call_valid_authwit_public,
    };
    
    // compression library
    use compressed_string::FieldCompressedString;

    // Constants for gas optimization
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    /// Storage structure for the SFT contract
    /// @param name The name of the token collection
    /// @param symbol The symbol of the token collection
    /// @param uri The base URI for token metadata
    /// @param private_balances Map of address to private SFT notes
    /// @param public_balances Map of (address, tokenId) to amount for public holdings
    /// @param token_exists Map to track which token IDs have been created
    /// @param token_supplies Map of token ID to total supply
    /// @param minter The address that can create new token types
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        uri: PublicImmutable<FieldCompressedString, Context>,
        
        // Private balances using SFTNote
        private_balances: Map<AztecAddress, PrivateSet<SFTNote, Context>, Context>,
        
        // Public balances: address -> token_id -> amount
        public_balances: Map<AztecAddress, Map<Field, PublicMutable<u128, Context>, Context>, Context>,
        
        // Track which token IDs exist
        token_exists: Map<Field, PublicMutable<bool, Context>, Context>,
        
        // Track total supply per token ID
        token_supplies: Map<Field, PublicMutable<u128, Context>, Context>,
        
        // Minter role
        minter: PublicImmutable<AztecAddress, Context>,
    }

    /// @notice Initializes the token collection with a minter
    /// @param name The name of the collection
    /// @param symbol The symbol of the collection
    /// @param uri The base URI for token metadata
    /// @param minter The address that can create new token types
    #[public]
    #[initializer]
    fn constructor_with_minter(
        name: str<31>, 
        symbol: str<31>, 
        uri: str<31>,
        minter: AztecAddress
    ) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.uri.initialize(FieldCompressedString::from_string(uri));
        storage.minter.initialize(minter);
    }

     /** ==========================================================
    * ======================= PRIVATE ==========================
    * ======================================================== */

    #[private]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        amount: u128,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);

        // Remove tokens from sender's private balance
        _remove_private_token_amount(storage.private_balances.at(from), token_id, amount);
        
        // Enqueue public call to increase recipient's public balance
        SFT::at(context.this_address())
            .update_public_balance_from_private_internal(to, token_id, amount)
            .enqueue(&mut context);
    }

    #[private]
    fn transfer_private_to_public_with_commitment(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        amount: u128,
        nonce: Field,
    ) -> PartialSFTNote {
        _validate_from_private(&mut context, from, nonce);

        // Remove tokens from sender's private balance
        _remove_private_token_amount(storage.private_balances.at(from), token_id, amount);
        
        // Enqueue public call to increase recipient's public balance
        SFT::at(context.this_address())
            .update_public_balance_from_private_internal(to, token_id, amount)
            .enqueue(&mut context);
        
        // Create commitment for privacy entrance
        let commitment = _initialize_transfer_commitment(&mut context, storage.private_balances, from, to);
        commitment
    }

    #[private]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        amount: u128,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);
        
        // Remove tokens from sender
        _remove_private_token_amount(storage.private_balances.at(from), token_id, amount);
        
        // Add tokens to recipient
        _add_private_tokens(
            &mut context,
            storage.private_balances.at(to),
            from,
            to,
            token_id,
            amount,
        );
    }

    #[private]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        token_id: Field,
        amount: u128,
        commitment: PartialSFTNote,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);
        
        // Remove tokens from sender
        _remove_private_token_amount(storage.private_balances.at(from), token_id, amount);
        
        // Enqueue public call to complete commitment with token ID and amount
        SFT::at(context.this_address())
            .transfer_token_to_commitment_internal(commitment, token_id, amount)
            .enqueue(&mut context);
    }

    #[private]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        amount: u128,
        nonce: Field,
    ) {
        _validate_from_private(&mut context, from, nonce);
        
        // Enqueue public call to decrease sender's public balance
        SFT::at(context.this_address())
            .update_public_balance_internal(from, AztecAddress::zero(), token_id, amount)
            .enqueue(&mut context);
        
        // Add tokens to recipient's private balance
        _add_private_tokens(
            &mut context,
            storage.private_balances.at(to),
            from,
            to,
            token_id,
            amount,
        );
    }

    /// @notice Initializes a transfer commitment
    /// @param context The context
    /// @param private_balances The private balances map
    /// @param from The sender address
    /// @param to The recipient address
    /// @return The partial SFT note for commitment
    #[contract_library_method]
    fn _initialize_transfer_commitment(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, PrivateSet<SFTNote, &mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
    ) -> PartialSFTNote {
        // Create partial note for commitment from sender to recipient
        let storage_slot = context.compute_slot_for_type(SFTNote::get_type_id(), 3);
        SFTNote::partial(to, storage_slot, context, to, from)
    }

    #[private]
    fn initialize_transfer_commitment(from: AztecAddress, to: AztecAddress) -> PartialSFTNote {
        _initialize_transfer_commitment(&mut context, storage.private_balances, from, to)
    }

    /** ==========================================================
    * ======================= PUBLIC ==========================
    * ======================================================== */

    #[public]
    #[public]
    fn transfer_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        amount: u128,
        nonce: Field,
    ) {}

    #[public]
    fn transfer_public_to_commitment(
        from: AztecAddress,
        token_id: Field,
        amount: u128,
        commitment: PartialSFTNote,
        nonce: Field,
    ) {}

    #[public]
    #[internal]
    fn store_commitment_in_storage_internal(commitment: PartialSFTNote) {}

    #[public]
    #[internal]
    fn transfer_token_to_commitment_internal(commitment: PartialSFTNote, token_id: Field, amount: u128) {
        // Verify token exists
        assert(storage.token_exists.at(token_id).read(), "token does not exist");
        
        // Complete the commitment with token ID and amount
        commitment.complete(token_id, amount, &mut context);
    }

    #[public]
    #[internal]
    fn update_public_balance_internal(from: AztecAddress, to: AztecAddress, token_id: Field, amount: u128) {
        // Verify token exists
        assert(storage.token_exists.at(token_id).read(), "token does not exist");
        
        // If from address is not zero, decrease their balance
        if (!from.eq(AztecAddress::zero())) {
            _decrease_public_balance(storage.public_balances, from, token_id, amount);
        }
        
        // If to address is not zero, increase their balance
        if (!to.eq(AztecAddress::zero())) {
            _increase_public_balance(storage.public_balances, to, token_id, amount);
        }
    }

    #[public]
    #[internal]
    fn update_public_token_owner_from_zero_internal(to: AztecAddress, token_id: Field, amount: u128) {
        // Verify token exists
        assert(storage.token_exists.at(token_id).read(), "token does not exist");
        
        // Update recipient's public balance
        _increase_public_balance(storage.public_balances, to, token_id, amount);
    }

    #[public]
    #[internal]
    fn set_sft_exists_internal(token_id: Field, exists: bool) {}
    
        
    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    /// @notice Mints tokens to a private address
    /// @dev Asserts that the caller is an authorized minter
    /// @param to The address of the recipient
    /// @param token_id The token ID to mint
    /// @param amount The amount to mint
    #[private]
    fn mint_private(to: AztecAddress, token_id: Field, amount: u128) {
        assert(token_id != 0, "zero token ID not supported");
        assert(amount != 0, "cannot mint zero amount");
        _validate_minter(context.msg_sender(), storage.minter.read());

        // Create and emit new note
        let note = SFTNote::new(token_id, amount, to);
        storage.private_balances.at(to).insert(note).emit(
            encode_and_encrypt_note(&mut context, to, to)
        );

        // Update token existence and supply
        _update_token_existence_and_supply(token_id, amount);
    }

    /// @notice Mints tokens to a public address
    /// @dev Asserts that the caller is an authorized minter
    /// @param to The address of the recipient
    /// @param token_id The token ID to mint
    /// @param amount The amount to mint
    #[public]
    fn mint_public(to: AztecAddress, token_id: Field, amount: u128) {
        assert(token_id != 0, "zero token ID not supported");
        assert(amount != 0, "cannot mint zero amount");
        _validate_minter(context.msg_sender(), storage.minter.read());

        // Update token existence and supply
        _update_token_existence_and_supply(token_id, amount);
        
        // Update recipient's balance
        _increase_public_balance(storage.public_balances, to, token_id, amount);
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns tokens from a private address
    /// @dev Asserts that the caller is token owner, removes private token amount
    /// @param from The address of the owner
    /// @param token_id The token ID to burn
    /// @param amount The amount to burn
    /// @param nonce The nonce for auth witness
    #[private]
    fn burn_private(from: AztecAddress, token_id: Field, amount: u128, nonce: Field) {
        assert(amount != 0, "cannot burn zero amount");
        _validate_from_private(&mut context, from, nonce);

        // Remove tokens from private balance
        _remove_private_token_amount(storage.private_balances.at(from), token_id, amount);
        
        // Update supply
        _decrease_token_supply(token_id, amount);
    }

    /// @notice Burns tokens from a public address
    /// @dev Asserts that token exists and that the caller is token owner
    /// @param from The address of the owner
    /// @param token_id The token ID to burn
    /// @param amount The amount to burn
    /// @param nonce The nonce for auth witness
    #[public]
    fn burn_public(from: AztecAddress, token_id: Field, amount: u128, nonce: Field) {
        assert(amount != 0, "cannot burn zero amount");
        _validate_from_public(&mut context, from, nonce);

        // Decrease public balance
        _decrease_public_balance(storage.public_balances, from, token_id, amount);
        
        // Update supply
        _decrease_token_supply(token_id, amount);
    }

    /** ==========================================================
     * ====================== VIEW FUNCTIONS =====================
     * ======================================================== */

    /// @notice Returns the public balance of an account for a token
    /// @param owner The address of the owner
    /// @param token_id The token ID to check
    /// @return The balance of the public balance
    #[public]
    #[view]
    fn balance_of_public(owner: AztecAddress, token_id: Field) -> pub u128 {
        storage.public_balances.at(owner).at(token_id).read()
    }

    /// @notice Returns the total supply of a token
    /// @param token_id The token ID to check
    /// @return The total supply of the token
    #[public]
    #[view]
    fn total_supply(token_id: Field) -> pub u128 {
        storage.token_supplies.at(token_id).read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    /// @notice Returns the private balance of an account for a token
    /// @param owner The address of the owner
    /// @param token_id The token ID to check
    /// @return The balance of the private balance
    #[utility]
    unconstrained fn balance_of_private(owner: AztecAddress, token_id: Field) -> u128 {
        let notes = storage.private_balances.at(owner).view_notes(
            NoteViewerOptions::new()
                .select(SFTNote::properties().token_id, Comparator.EQ, token_id)
        );
        
        let mut total = 0;
        for i in 0..notes.len() {
            total += notes.get_unchecked(i).get_amount();
        }
        total
    }

        /** ==========================================================
     * ======================= TOKEN LIBRARIES ===================
     * ======================================================== */

    /// @notice Updates token existence and supply tracking
    /// @param token_id The token ID to update
    /// @param amount The amount to add to supply
    #[contract_library_method]
    fn _update_token_existence_and_supply(token_id: Field, amount: u128) {
        // Mark token as existing if not already
        if (!storage.token_exists.at(token_id).read()) {
            storage.token_exists.at(token_id).write(true);
        }
        
        // Update total supply
        let current_supply = storage.token_supplies.at(token_id).read();
        storage.token_supplies.at(token_id).write(current_supply + amount);
    }

    /// @notice Decreases the total supply of a token
    /// @param token_id The token ID to update
    /// @param amount The amount to subtract from supply
    #[contract_library_method]
    fn _decrease_token_supply(token_id: Field, amount: u128) {
        let current_supply = storage.token_supplies.at(token_id).read();
        assert(current_supply >= amount, "insufficient supply");
        storage.token_supplies.at(token_id).write(current_supply - amount);
    }

    /// @notice Removes amount of tokens from private balance
    /// @param private_set The private note set
    /// @param token_id The token ID to remove
    /// @param amount The amount to remove
    #[contract_library_method]
    fn _remove_private_token_amount(
        private_set: PrivateSet<SFTNote, &mut PrivateContext>,
        token_id: Field,
        amount: u128,
    ) {
        let notes = private_set.pop_notes(NoteGetterOptions::new()
            .select(SFTNote::properties().token_id, Comparator.EQ, token_id)
            .set_limit(1));
        assert(notes.len() == 1, "token not found");
        
        let note = notes[0];
        assert(note.get_amount() >= amount, "insufficient balance");
        
        // If there's remaining amount, create new note
        if (note.get_amount() > amount) {
            let remaining = note.get_amount() - amount;
            let new_note = SFTNote::new(token_id, remaining, note.owner);
            private_set.insert(new_note);
        }
    }

    /// @notice Updates the public balance of an account
    /// @param public_balances The public balances map
    /// @param account The account to update
    /// @param token_id The token ID to update
    /// @param amount The amount to add
    #[contract_library_method]
    fn _increase_public_balance(
        public_balances: Map<AztecAddress, Map<Field, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>, &mut PublicContext>,
        account: AztecAddress,
        token_id: Field,
        amount: u128,
    ) {
        let new_balance = public_balances.at(account).at(token_id).read() + amount;
        public_balances.at(account).at(token_id).write(new_balance);
    }

    /// @notice Decreases the public balance of an account
    /// @param public_balances The public balances map
    /// @param account The account to update
    /// @param token_id The token ID to update
    /// @param amount The amount to subtract
    #[contract_library_method]
    fn _decrease_public_balance(
        public_balances: Map<AztecAddress, Map<Field, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>, &mut PublicContext>,
        account: AztecAddress,
        token_id: Field,
        amount: u128,
    ) {
        let current_balance = public_balances.at(account).at(token_id).read();
        assert(current_balance >= amount, "insufficient balance");
        public_balances.at(account).at(token_id).write(current_balance - amount);
    }

    /// @notice Validates that caller has permission to act on behalf of from address
    /// @param context The private context
    /// @param from The from address
    /// @param nonce The nonce for auth witness
    #[contract_library_method]
    fn _validate_from_private(context: &mut PrivateContext, from: AztecAddress, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }

    /// @notice Validates that caller has permission to act on behalf of from address in public context
    /// @param context The public context
    /// @param from The from address
    /// @param nonce The nonce for auth witness
    #[contract_library_method]
    fn _validate_from_public(context: &mut PublicContext, from: AztecAddress, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }

    /// @notice Validates that caller is the minter
    /// @param caller The caller address
    /// @param minter The minter address
    #[contract_library_method]
    fn _validate_minter(caller: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(caller), "caller is not minter");
    }

    /// @notice Adds tokens to a recipient's private balance
    /// @param context The context of the private call
    /// @param private_set The private note set
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The token ID to add
    /// @param amount The amount to add
    #[contract_library_method]
    fn _add_private_tokens(
        context: &mut PrivateContext,
        private_set: PrivateSet<SFTNote, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        amount: u128,
    ) {
        let new_note = SFTNote::new(token_id, amount, to);
        private_set.insert(new_note).emit(encode_and_encrypt_note(context, to, from));
    }

    #[public]
    #[internal]
    fn update_public_balance_from_private_internal(to: AztecAddress, token_id: Field, amount: u128) {
        // Verify token exists
        assert(storage.token_exists.at(token_id).read(), "token does not exist");
        
        // Increase recipient's public balance
        _increase_public_balance(storage.public_balances, to, token_id, amount);
    }
}
