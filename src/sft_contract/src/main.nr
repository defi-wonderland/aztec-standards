mod types;

use aztec::macros::aztec;

#[aztec]
pub contract SFT {
    // aztec library
    use aztec::{
        authwit::auth::{
            assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
        },
        context::PrivateContext,
        macros::{
            functions::{initializer, internal, private, public, utility, view},
            storage::storage,
        },
        messages::logs::note::encode_and_encrypt_note,
        note::{constants::MAX_NOTES_PER_PAGE, note_interface::NoteProperties},
        prelude::{
            AztecAddress, Map, NoteGetterOptions, NoteViewerOptions, PrivateSet, PublicContext,
            PublicImmutable, PublicMutable,
        },
        utils::comparison::Comparator,
    };
    // compression library
    use compressed_string::FieldCompressedString;
    // sft note struct
    use crate::types::sft_note::{SFTNote, PartialSFTNote};

    /// Storage layout for Semi-Fungible Token (SFT) contract
    /// @param name The name of the SFT collection
    /// @param symbol The symbol of the SFT collection
    /// @param minter The account permissioned to mint new tokens
    /// @param private_sfts Private SFT ownership using nested mapping (token_id -> address -> PrivateSet<SFTNote>)
    /// @param public_balances Public SFT item IDs using nested mapping (token_id -> address -> array of item_ids)
    /// @param total_supply Total supply of each token type
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
        private_sfts: Map<Field, Map<AztecAddress, PrivateSet<SFTNote, Context>, Context>, Context>,
        public_balances: Map<Field, Map<AztecAddress, PublicMutable<[Field; 32], Context>, Context>, Context>, // 32 is max number of items per token type
        total_supply: Map<Field, PublicMutable<u128, Context>, Context>,
        upgrade_authority: PublicImmutable<AztecAddress, Context>,
    }

    /** ==========================================================
     * ===================== INITIALIZERS ========================
     * ======================================================== */

    /// @notice Initializes the SFT contract with a minter
    /// @param name The name of the SFT collection
    /// @param symbol The symbol of the SFT collection
    /// @param minter The address of the minter (zero address to disable minting)
    /// @param upgrade_authority The address of the upgrade authority (zero address if not upgradeable)
    #[public]
    #[initializer]
    fn constructor_with_minter(
        name: str<31>,
        symbol: str<31>,
        minter: AztecAddress,
        upgrade_authority: AztecAddress,
    ) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.minter.initialize(minter);
        storage.upgrade_authority.initialize(upgrade_authority);
    }

    /** ==========================================================
     * ========================= PUBLIC ==========================
     * ======================================================== */
     
    /// @notice Creates a new token type with a total supply of 0
    /// @param token_id The ID of the new token type
    #[public]
    fn create_token_type(token_id: Field) {
        _validate_minter(context.msg_sender(), storage.minter.read());
        storage.total_supply.at(token_id).write(0);
    }

    /// @notice Stores a commitment in storage
    /// @param commitment The commitment to store
    #[public]
    #[internal]
    fn store_commitment_in_storage_internal(commitment: PartialSFTNote) {
        _store_commitment_in_storage(&mut context, commitment);
    }

    /** ==========================================================
     * ====================== VIEW FUNCTIONS =====================
     * ======================================================== */

    /// @return the name of the SFT collection
    #[public]
    #[view]
    fn public_get_name() -> FieldCompressedString {
        storage.name.read()
    }

    /// @return the symbol of the SFT collection
    #[public]
    #[view]
    fn public_get_symbol() -> FieldCompressedString {
        storage.symbol.read()
    }

    /// @notice Returns the public balance of `owner` for `token_id`
    /// @param owner The address of the owner
    /// @param token_id The ID of the token type
    /// @return The balance of the public balance of `owner` for `token_id`
    #[public]
    #[view]
    fn public_balance_of(owner: AztecAddress, token_id: Field) -> u128 {
        let item_ids = storage.public_balances.at(token_id).at(owner).read();
        item_ids.len() as u128
    }

    /// @notice Returns the item IDs owned by `owner` for `token_id`
    /// @param owner The address of the owner
    /// @param token_id The ID of the token type
    /// @return The item IDs owned by `owner` for `token_id`
    #[public]
    #[view]
    fn public_item_ids(owner: AztecAddress, token_id: Field) -> [Field; 32] {
        storage.public_balances.at(token_id).at(owner).read()
    }

    /// @notice Returns the total supply of `token_id`
    /// @param token_id The ID of the token type
    /// @return The total supply of `token_id`
    #[public]
    #[view]
    fn total_supply(token_id: Field) -> u128 {
        storage.total_supply.at(token_id).read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    /// @notice Returns the private balance of `owner` for `token_id` starting from a specific offset
    /// @param owner The address of the owner
    /// @param token_id The ID of the token type
    /// @param page_index The offset to start counting from (for pagination)
    /// @return The number of items of `token_id` owned privately by `owner`
    #[utility]
    pub unconstrained fn balance_of_private_by_token_id(owner: AztecAddress, token_id: Field, page_index: u32) -> u128 {
        let offset = page_index * MAX_NOTES_PER_PAGE;
        let mut options = NoteViewerOptions::new();
        let sfts = storage.private_sfts.at(token_id).at(owner).view_notes(options.set_offset(offset));
        sfts.len() as u128
    }

    /// @notice Returns an array of item IDs owned by `owner` for `token_id` starting from a specific offset
    /// @param owner The address of the owner
    /// @param token_id The ID of the token type
    /// @param page_index The offset to start counting from (for pagination)
    /// @return The number of items of `token_id` owned privately by `owner`
    /// @return A flag indicating whether a page limit was reached
    #[utility]
    pub unconstrained fn get_private_sfts_by_token_id(
        owner: AztecAddress,
        token_id: Field,
        page_index: u32,
    ) -> pub ([Field; MAX_NOTES_PER_PAGE], bool) {
        let offset = page_index * MAX_NOTES_PER_PAGE;
        let mut options = NoteViewerOptions::new();
        let sfts = storage.private_sfts.at(token_id).at(owner).view_notes(options.set_offset(offset));
        
        let mut owned_item_ids = [0; MAX_NOTES_PER_PAGE];
        for i in 0..options.limit {
            if i < sfts.len() {
                owned_item_ids[i] = sfts.get_unchecked(i).item_id;
            }
        }
        let page_limit_reached = sfts.len() == options.limit;
        (owned_item_ids, page_limit_reached)
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// @notice Stores a commitment in storage
    /// @param context The context of the public call
    /// @param commitment The commitment to store
    #[contract_library_method]
    fn _store_commitment_in_storage(context: &mut PublicContext, commitment: PartialSFTNote) {
        context.storage_write(commitment.commitment(), true);
    }

    #[contract_library_method]
    fn _initialize_transfer_commitment(
        context: &mut PrivateContext,
        private_sft_set: Map<Field, Map<AztecAddress, PrivateSet<SFTNote, &mut PrivateContext>, &mut PrivateContext>, &mut PrivateContext>,
        token_id: Field,
        from: AztecAddress,
        to: AztecAddress,
        completer: AztecAddress,
    ) -> PartialSFTNote {
        let commitment = SFTNote::partial(
            to,
            private_sft_set.at(token_id).at(to).storage_slot,
            context,
            to,
            from,
            completer,
        );
        SFT::at(context.this_address()).store_commitment_in_storage_internal(commitment).enqueue(
            context,
        );
        commitment
    }

    #[contract_library_method]
    fn _update_private_token_owner(
        context: &mut PrivateContext,
        private_sft_set: Map<Field, Map<AztecAddress, PrivateSet<SFTNote, &mut PrivateContext>, &mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        item_id: Field,
    ) {
        let new_note = SFTNote::new(token_id, item_id, to);
        private_sft_set.at(token_id).at(to).insert(new_note).emit(encode_and_encrypt_note(context, to, from));
    }

    #[contract_library_method]
    fn _remove_private_token_owner(
        private_sft_set: Map<Field, Map<AztecAddress, PrivateSet<SFTNote, &mut PrivateContext>, &mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress,
        token_id: Field,
        item_id: Field,
    ) {
        let notes = private_sft_set.at(token_id).at(from).pop_notes(NoteGetterOptions::new()
            .select(SFTNote::properties().item_id, Comparator.EQ, item_id)
            .set_limit(1));
        assert(notes.len() == 1, "sft not found in private to public");
    }

    #[contract_library_method]
    fn _update_public_item_ids(
        public_item_ids: Map<Field, Map<AztecAddress, PublicMutable<[Field; 32], &mut PublicContext>, &mut PublicContext>, &mut PublicContext>,
        to: AztecAddress,
        token_id: Field,
        item_id: Field,
    ) {
        let mut item_ids = public_item_ids.at(token_id).at(to).read();
        let mut found_empty = false;
        for i in 0..32 {
            if (item_ids[i] == 0) & (!found_empty) {
                item_ids[i] = item_id;
                found_empty = true;
            }
        }
        assert(found_empty, "no empty slots in item_ids array");
        public_item_ids.at(token_id).at(to).write(item_ids);
    }

    /// @notice Removes a specific item ID from a user's public collection
    /// @param public_item_ids The storage pointer to the public item IDs
    /// @param from The address of the owner
    /// @param token_id The ID of the token type
    /// @param item_id The specific item ID to remove
    #[contract_library_method]
    fn _remove_public_item_id(
        public_item_ids: Map<Field, Map<AztecAddress, PublicMutable<[Field; 32], &mut PublicContext>, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        token_id: Field,
        item_id: Field,
    ) {
        let mut item_ids = public_item_ids.at(token_id).at(from).read();
        let mut found_item = false;
        for i in 0..32 {
            if (item_ids[i] == item_id) & (!found_item) {
                item_ids[i] = 0;
                found_item = true;
            }
        }
        assert(found_item, "item not found in public collection");
        public_item_ids.at(token_id).at(from).write(item_ids);
    }

    #[contract_library_method]
    fn _transfer_token_to_commitment(
        context: &mut PublicContext,
        commitment: PartialSFTNote,
        token_id: Field,
        item_id: Field,
        completer: AztecAddress,
    ) {
        assert(context.storage_read(commitment.commitment()), "invalid commitment");
        commitment.complete(context, completer, token_id, item_id);
    }

    #[contract_library_method]
    fn _validate_public_token_owner(
        public_item_ids: Map<Field, Map<AztecAddress, PublicMutable<[Field; 32], &mut PublicContext>, &mut PublicContext>, &mut PublicContext>, 
        from: AztecAddress, 
        token_id: Field,
        item_id: Field,
      ) {
        let item_ids = public_item_ids.at(token_id).at(from).read();
        let mut owner_of_item_id = false;
        for i in 0..32 {
            if item_ids[i] != 0 {
                owner_of_item_id = true;
            }
        }
        assert(owner_of_item_id, "caller owns no tokens of this type");
    }

    /// @notice Validates that the caller is an authorized minter
    /// @param sender The address of the caller
    /// @param minter The address of the minter
    #[contract_library_method]
    fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }

    /** ==========================================================
     * ================== AUTH LIBRARIES =========================
     * ======================================================== */

    /// @notice Validates that the caller possesses authwit from the `from` address or the caller is the `from` address
    /// @param context The context of the private call
    /// @param from The address of the sender
    #[contract_library_method]
    fn _validate_from_private(context: &mut PrivateContext, from: AztecAddress) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(context, from);
        }
    }

    /// @notice Validates that the caller possesses authwit from the `from` address or the caller is the `from` address
    /// @param context The context of the public call
    /// @param from The address of the sender
    #[contract_library_method]
    unconstrained fn _validate_from_public(context: &mut PublicContext, from: AztecAddress) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(context, from);
        }
    }

}
