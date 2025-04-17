mod types;
mod test;

use aztec::macros::aztec;

#[aztec]
pub contract NFT {
    // nft note structs
    use crate::types::nft_note::{NFTNote, PartialNFTNote};
    // aztec library
    use aztec::{
        context::PrivateContext,
        macros::{
            functions::{initializer, internal, private, public, utility, view},
            storage::storage,
        },
        note::{constants::MAX_NOTES_PER_PAGE, note_interface::NoteProperties},
        prelude::{
            AztecAddress, Map, NoteGetterOptions, NoteViewerOptions, PrivateSet,
            PublicContext, PublicImmutable, PublicMutable,
        },
        protocol_types::traits::Serialize,
        utils::comparison::Comparator,
    };
    // authorized witness library
    use authwit::auth::{
        assert_current_call_valid_authwit, assert_current_call_valid_authwit_public
    };
    // compression library
    use compressed_string::FieldCompressedString;
    // encryption library
    use aztec::messages::logs::note::encode_and_encrypt_note;

    /// @param symbol The symbol of the NFT
    /// @param name The name of the NFT
    /// @param private_nfts A map from address to a private set of NFTNotes owned by that address
    /// @param nft_exists A map from token ID to a boolean indicating if the NFT exists
    /// @param public_owners A map from token ID to the public owner of the NFT
    /// @param minter The address that can mint
    #[storage]
    struct Storage<Context> {
        symbol: PublicImmutable<FieldCompressedString, Context>,
        name: PublicImmutable<FieldCompressedString, Context>,
        private_nfts: Map<AztecAddress, PrivateSet<NFTNote, Context>, Context>,
        nft_exists: Map<Field, PublicMutable<bool, Context>, Context>,
        public_owners: Map<Field, PublicMutable<AztecAddress, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
    }

    /// @dev Initializes the token with a minter
    /// @param name The name of the NFT
    /// @param symbol The symbol of the NFT
    /// @param minter The address of the minter
    #[public]
    #[initializer]
    fn constructor_with_minter(name: str<31>, symbol: str<31>, minter: AztecAddress) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.minter.initialize(minter);
    }

    /** ==========================================================
     * ========================= PRIVATE =========================
     * ======================================================== */

    #[private]
    fn transfer_private_to_public(from: AztecAddress, to: AztecAddress, token_id: Field, nonce: Field) {
        _validate_from_private(&mut context, from, nonce);
        _remove_private_token_owner(storage.private_nfts.at(from), token_id);
        NFT::at(context.this_address()).update_public_token_owner_internal(from, to, token_id, true).enqueue(
            &mut context,
        );
    }

    #[private]
    fn transfer_private_to_public_with_commitment(from: AztecAddress, to: AztecAddress, token_id: Field, commitment: PartialNFTNote, nonce: Field) -> PartialNFTNote {
        _validate_from_private(&mut context, from, nonce);
        _remove_private_token_owner(storage.private_nfts.at(from), token_id);
        NFT::at(context.this_address()).update_public_token_owner_internal(from, to, token_id, true).enqueue(
            &mut context,
        );
        let commitment = _initialize_transfer_commitment(&mut context, storage.private_nfts, from, to);
        commitment
    }

    #[private]
    fn transfer_private_to_private(from: AztecAddress, to: AztecAddress, token_id: Field, nonce: Field) {
        _validate_from_private(&mut context, from, nonce);
        let private_nfts = storage.private_nfts;
        _remove_private_token_owner(private_nfts.at(from), token_id);
        _update_private_token_owner(&mut context, private_nfts.at(to), from, to, token_id);
    }

    #[private]
    fn transfer_private_to_commitment(from: AztecAddress, token_id: Field, commitment: PartialNFTNote, nonce: Field) {
        _validate_from_private(&mut context, from, nonce);
        _remove_private_token_owner(storage.private_nfts.at(from), token_id);
        NFT::at(context.this_address()).transfer_token_to_commitment_internal(commitment, token_id).enqueue(
            &mut context,
        );
    }

    #[private]
    fn transfer_public_to_private(from: AztecAddress, to: AztecAddress, token_id: Field, nonce: Field) {
        _validate_from_private(&mut context, from, nonce);
        NFT::at(context.this_address()).update_public_token_owner_internal(from, AztecAddress::zero(), token_id, false).enqueue(
            &mut context,
        );
        _update_private_token_owner(&mut context, storage.private_nfts.at(to), from, to, token_id);
    }

    #[private]
    fn initialize_transfer_commitment(from: AztecAddress, to: AztecAddress) -> PartialNFTNote {
        _initialize_transfer_commitment(&mut context, storage.private_nfts, from, to)
    }

    /** ==========================================================
     * ========================= PUBLIC ==========================
     * ======================================================== */

    #[public]
    fn transfer_public_to_public(from: AztecAddress, to: AztecAddress, token_id: Field, nonce: Field) {
        _validate_from_public(&mut context, from, nonce);
        _update_public_token_owner(storage.public_owners, from, to, token_id, false);
    }

    #[public]
    fn transfer_public_to_commitment(from: AztecAddress, token_id: Field, commitment: PartialNFTNote, nonce: Field,) {
        _validate_from_public(&mut context, from, nonce);
        _update_public_token_owner(storage.public_owners, from, AztecAddress::zero(), token_id, false);
        _transfer_token_to_commitment(&mut context, commitment, token_id);
    }

    #[public]
    #[internal]
    fn store_commitment_in_storage_internal(commitment: PartialNFTNote) {
        _store_commitment_in_storage(&mut context, commitment);
    }

    #[public]
    #[internal]
    fn transfer_token_to_commitment_internal(commitment: PartialNFTNote, token_id: Field) {
        _transfer_token_to_commitment(&mut context, commitment, token_id);
    }

    #[public]
    #[internal]
    fn update_public_token_owner_internal(
        from: AztecAddress, 
        to: AztecAddress,
        token_id: Field,
        from_private: bool,
    ) {
        _update_public_token_owner(storage.public_owners, from, to, token_id, from_private);
    }

    #[public]
    #[internal]
    fn update_nft_exists_internal(
        token_id: Field, 
        exists: bool,
        ) {
        storage.nft_exists.at(token_id).write(exists);
    }

    /** ==========================================================
     * ====================== VIEW FUNCTIONS =====================
     * ======================================================== */

    #[public]
    #[view]
    fn public_get_name() -> pub FieldCompressedString {
        storage.name.read()
    }

    #[public]
    #[view]
    fn public_get_symbol() -> pub FieldCompressedString {
        storage.symbol.read()
    }

    #[public]
    #[view]
    fn owner_of(token_id: Field) -> AztecAddress {
        storage.public_owners.at(token_id).read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    /// Returns an array of token IDs owned by `owner` in private and a flag indicating whether a page limit was
    /// reached. Starts getting the notes from page with index `page_index`. Zero values in the array are placeholder
    /// values for non-existing notes.
    #[utility]
    unconstrained fn get_private_nfts(
        owner: AztecAddress,
        page_index: u32,
    ) -> pub ([Field; MAX_NOTES_PER_PAGE], bool) {
        let offset = page_index * MAX_NOTES_PER_PAGE;
        let mut options = NoteViewerOptions::new();
        let nfts = storage.private_nfts.at(owner).view_notes(options.set_offset(offset));

        let mut owned_nft_ids = [0; MAX_NOTES_PER_PAGE];
        for i in 0..options.limit {
            if i < nfts.len() {
                owned_nft_ids[i] = nfts.get_unchecked(i).token_id;
            }
        }

        let page_limit_reached = nfts.len() == options.limit;
        (owned_nft_ids, page_limit_reached)
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    #[private]
    fn mint_private(to: AztecAddress, token_id: Field) {
        _validate_minter(context.msg_sender(), storage.minter.read());
        let nft = NFT::at(context.this_address());
        nft.validate_token_to_mint_internal(token_id).enqueue(
            &mut context,
        );
        nft.update_nft_exists_internal(token_id, true).enqueue(
            &mut context,
        );
        storage.private_nfts.at(to).insert(NFTNote::new(token_id, to));
    }

    #[public]
    fn mint_public(to: AztecAddress, token_id: Field) {
        _validate_minter(context.msg_sender(), storage.minter.read());
        validate_token_to_mint_internal(token_id);
        update_nft_exists_internal(token_id, true);
        storage.public_owners.at(token_id).write(to);
    }

    #[public]
    #[internal]
    fn validate_token_to_mint_internal(token_id: Field) {
        assert(token_id != 0, "zero token ID not supported");
        assert(storage.nft_exists.at(token_id).read() == false, "token already exists");
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @dev if token does not exist it will revert on _remove_private_token_owner call
    #[private]
    fn burn_private(from: AztecAddress, token_id: Field, nonce: Field) {
        _validate_from_private(&mut context, from, nonce);
        _remove_private_token_owner(storage.private_nfts.at(from), token_id);
        NFT::at(context.this_address()).update_nft_exists_internal(token_id, false).enqueue(&mut context);
    }

    #[public]
    fn burn_public(from: AztecAddress, token_id: Field, nonce: Field) {
        assert(storage.nft_exists.at(token_id).read(), "token does not exist");
        _validate_from_public(&mut context, from, nonce);
        _update_public_token_owner(storage.public_owners, from, AztecAddress::zero(), token_id, false);
        storage.nft_exists.at(token_id).write(false);
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    #[contract_library_method]
    fn _store_commitment_in_storage(context: &mut PublicContext, commitment: PartialNFTNote) {
        context.storage_write(commitment.commitment(), true);
    }

    #[contract_library_method]
    fn _initialize_transfer_commitment(
        context: &mut PrivateContext,
        private_nfts: Map<AztecAddress, PrivateSet<NFTNote, &mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
    ) -> PartialNFTNote {
        let commitment = NFTNote::partial(
            to,
            private_nfts.at(to).storage_slot,
            context,
            to,
            from,
        );
        NFT::at(context.this_address()).store_commitment_in_storage_internal(commitment).enqueue(context);
        commitment
    }

    #[contract_library_method]
    fn _update_private_token_owner(
        context: &mut PrivateContext,
        private_nft_set: PrivateSet<NFTNote, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
    ) {
        let new_note = NFTNote::new(token_id, to);
        private_nft_set.insert(new_note).emit(encode_and_encrypt_note(context, to, from));
    }

    #[contract_library_method]
    fn _remove_private_token_owner(
        private_nft_set: PrivateSet<NFTNote, &mut PrivateContext>,
        token_id: Field,
    ) {
        let notes = private_nft_set.pop_notes(NoteGetterOptions::new()
            .select(NFTNote::properties().token_id, Comparator.EQ, token_id)
            .set_limit(1));
        assert(notes.len() == 1, "nft not found in private to public");
    }

    #[contract_library_method]
    fn _update_public_token_owner(
        public_owners: Map<Field, PublicMutable<AztecAddress, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress, 
        to: AztecAddress,
        token_id: Field,
        from_private: bool,
    ) {
        let owner = public_owners.at(token_id).read();
        if from_private {
            assert(owner.eq(AztecAddress::zero()), "token has public owner");
        } else {
            assert(owner.eq(from), "caller is not owner");
        }
        public_owners.at(token_id).write(to);
    }

    #[contract_library_method]
    fn _transfer_token_to_commitment(
        context: &mut PublicContext,
        commitment: PartialNFTNote,
        token_id: Field,
    ) {
        // We verify that the commitment we're completing is valid (i.e. it uses the correct state variable's storage
        // slot, and it is internally consistent). We *could* clear the storage since each commitment should only be
        // used once, but since the AVM offers no gas refunds for doing so this would just make the transaction be more
        // expensive.
        assert(context.storage_read(commitment.commitment()), "invalid commitment");
        commitment.complete(token_id, context);
    }

    /// Validates that the caller is an authorized minter
    #[contract_library_method]
    fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }

    /** ==========================================================
     * ================== AUTH LIBRARIES =========================
     * ======================================================== */

    /// Validates that a user can perform operations on behalf of `from` in a private context.
    /// If the caller is not `from`, then they must have an authentication witness.
    #[contract_library_method]
    fn _validate_from_private(context: &mut PrivateContext, from: AztecAddress, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }

    /// Validates that a user can perform operations on behalf of `from` in a public context.
    /// If the caller is not `from`, then they must have an authentication witness.
    #[contract_library_method]
    unconstrained fn _validate_from_public(
        context: &mut PublicContext,
        from: AztecAddress,
        nonce: Field,
    ) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }
}
