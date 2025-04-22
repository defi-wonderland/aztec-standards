mod types;
mod test;

use aztec::macros::aztec;

#[aztec]
pub contract NFT {
    // nft note structs
    use crate::types::nft_note::{NFTNote, PartialNFTNote};
    // aztec library
    use aztec::{
        messages::logs::note::encode_and_encrypt_note,
        macros::{
            functions::{initializer, internal, private, public, view, utility},
            storage::storage,
        },
        note::{constants::MAX_NOTES_PER_PAGE, note_interface::NoteProperties},
        prelude::{
            AztecAddress, Map, NoteGetterOptions, NoteViewerOptions, PrivateContext, PrivateSet,
            PublicContext, PublicImmutable, PublicMutable,
        },
        protocol_types::traits::Serialize,
        utils::comparison::Comparator,
    };
    // authorized witness library
    use authwit::auth::{
        assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
        compute_authwit_nullifier,
    };
    // compression library
    use compressed_string::FieldCompressedString;
    // aztec protocol types
    use aztec::protocol_types::traits::ToField;
    // std library
    use std::meta::derive;

    /// @param symbol The symbol of the NFT
    /// @param name The name of the NFT
    /// @param private_nfts The NFTs owned by each address in private
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

    // Transfers token with `token_id` from public balance of message sender to a private balance of `to`.
    #[private]
    fn transfer_to_private(to: AztecAddress, token_id: Field) {
        let from = context.msg_sender();

        let nft = NFT::at(context.this_address());

        // We prepare the private balance increase.
        let commitment = _prepare_private_balance_increase(to, &mut context, storage);

        // At last we finalize the transfer. Usage of the `unsafe` method here is safe because we set the `from`
        // function argument to a message sender, guaranteeing that he can transfer only his own NFTs.
        nft._finalize_transfer_to_private_unsafe(from, token_id, commitment).enqueue(&mut context);
    }

    /// Prepares an increase of private balance of `to` (commitment). The increase needs to be finalized by calling
    /// `finalize_transfer_to_private` with the returned commitment.
    #[private]
    fn prepare_private_balance_increase(to: AztecAddress) -> PartialNFTNote {
        _prepare_private_balance_increase(to, &mut context, storage)
    }

    #[private]
    fn transfer_in_private(from: AztecAddress, to: AztecAddress, token_id: Field, nonce: Field) {
        _validate_from_private(&mut context, from, nonce);

        let nfts = storage.private_nfts;

        let notes = nfts.at(from).pop_notes(NoteGetterOptions::new()
            .select(NFTNote::properties().token_id, Comparator.EQ, token_id)
            .set_limit(1));
        assert(notes.len() == 1, "NFT not found when transferring");

        let new_note = NFTNote::new(token_id, to);

        nfts.at(to).insert(new_note).emit(encode_and_encrypt_note(&mut context, to, from));
    }

    #[private]
    fn transfer_to_public(from: AztecAddress, to: AztecAddress, token_id: Field, nonce: Field) {
        _validate_from_private(&mut context, from, nonce);

        let notes = storage.private_nfts.at(from).pop_notes(NoteGetterOptions::new()
            .select(NFTNote::properties().token_id, Comparator.EQ, token_id)
            .set_limit(1));
        assert(notes.len() == 1, "NFT not found when transferring to public");

        NFT::at(context.this_address())._finish_transfer_to_public(to, token_id).enqueue(
            &mut context,
        );
    }

    /** ==========================================================
     * ========================= PUBLIC ==========================
     * ======================================================== */

    #[public]
    fn transfer_in_public(from: AztecAddress, to: AztecAddress, token_id: Field, nonce: Field) {
        _validate_from_public(&mut context, from, nonce);

        let public_owners_storage = storage.public_owners.at(token_id);
        assert(public_owners_storage.read().eq(from), "invalid owner");

        public_owners_storage.write(to);
    }

    /// Finalizes a transfer of NFT with `token_id` from public balance of `from` to a private balance of `to`.
    /// The transfer must be prepared by calling `prepare_private_balance_increase` first and the resulting
    /// `commitment` must be passed as an argument to this function.
    #[public]
    fn finalize_transfer_to_private(token_id: Field, commitment: PartialNFTNote) {
        let from = context.msg_sender();
        _finalize_transfer_to_private(from, token_id, commitment, &mut context, storage);
    }

    #[public]
    #[internal]
    fn _store_nft_set_commitment(commitment: PartialNFTNote) {
        // We store the commitment in a slot equal to its commitment. This is safe because the commitment is computed
        // using a generator different from the one used to compute storage slots, so there can be no collisions.
        // We could consider storing all pending commitments in e.g. some array, but ultimately this is pointless: all
        // we need to verify is that the note is valid.
        context.storage_write(commitment.commitment(), true);
    }

    #[public]
    #[internal]
    fn _finalize_transfer_to_private_unsafe(
        from: AztecAddress,
        token_id: Field,
        commitment: PartialNFTNote,
    ) {
        _finalize_transfer_to_private(from, token_id, commitment, &mut context, storage);
    }

    #[public]
    #[internal]
    fn _finish_transfer_to_public(to: AztecAddress, token_id: Field) {
        storage.public_owners.at(token_id).write(to);
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

    // Returns zero address when the token does not have a public owner. Reverts if the token does not exist.
    #[public]
    #[view]
    fn owner_of(token_id: Field) -> AztecAddress {
        assert(storage.nft_exists.at(token_id).read(), "token does not exist");
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
        let notes = storage.private_nfts.at(owner).view_notes(options.set_offset(offset));

        let mut owned_nft_ids = [0; MAX_NOTES_PER_PAGE];
        for i in 0..options.limit {
            if i < notes.len() {
                owned_nft_ids[i] = notes.get_unchecked(i).token_id;
            }
        }

        let page_limit_reached = notes.len() == options.limit;
        (owned_nft_ids, page_limit_reached)
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    #[public]
    fn mint(to: AztecAddress, token_id: Field) {
        assert(token_id != 0, "zero token ID not supported");
        _validate_minter(context.msg_sender(), storage.minter.read());
        assert(storage.nft_exists.at(token_id).read() == false, "token already exists");

        storage.nft_exists.at(token_id).write(true);

        storage.public_owners.at(token_id).write(to);
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

     // todo: add burn function?

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// This function exists separately from `prepare_private_balance_increase` solely as an optimization as it allows
    /// us to have it inlined in the `transfer_to_private` function which results in one less kernel iteration.
    ///
    /// TODO(#9180): Consider adding macro support for functions callable both as an entrypoint and as an internal
    /// function.
    #[contract_library_method]
    fn _prepare_private_balance_increase(
        to: AztecAddress,
        context: &mut PrivateContext,
        storage: Storage<&mut PrivateContext>,
    ) -> PartialNFTNote {
        // We create a commitment with unpopulated/zero token id for 'to'
        let commitment = NFTNote::partial(
            to,
            storage.private_nfts.at(to).storage_slot,
            context,
            to,
            context.msg_sender(),
        );

        NFT::at(context.this_address())._store_nft_set_commitment(commitment).enqueue(context);

        commitment
    }

    #[contract_library_method]
    fn _finalize_transfer_to_private(
        from: AztecAddress,
        token_id: Field,
        commitment: PartialNFTNote,
        context: &mut PublicContext,
        storage: Storage<&mut PublicContext>,
    ) {
        let public_owners_storage = storage.public_owners.at(token_id);
        assert(public_owners_storage.read().eq(from), "invalid NFT owner");

        // Set the public NFT owner to zero
        public_owners_storage.write(AztecAddress::zero());

        // We verify that the commitment we're completing is valid (i.e. it uses the correct state variable's storage
        // slot, and it is internally consistent). We *could* clear the storage since each commitment should only be
        // used once, but since the AVM offers no gas refunds for doing so this would just make the transaction be more
        // expensive.
        assert(context.storage_read(commitment.commitment()), "Invalid commitment");
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
