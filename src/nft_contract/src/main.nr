pub mod types;
pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract NFT {
    // aztec library
    use aztec::{
        authwit::auth::{
            assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
        },
        context::{PrivateContext, PublicContext},
        macros::{functions::{external, initializer, internal, only_self, view}, storage::storage},
        messages::message_delivery::MessageDelivery,
        note::{
            constants::MAX_NOTES_PER_PAGE, note_getter_options::NoteGetterOptions,
            note_interface::NoteProperties, note_viewer_options::NoteViewerOptions,
        },
        protocol::{
            address::AztecAddress,
            constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            contract_class_id::ContractClassId,
            traits::{FromField, ToField},
        },
        state_vars::{Map, Owned, PrivateSet, PublicImmutable, PublicMutable, StateVariable},
        utils::comparison::Comparator,
    };
    // compression library
    use compressed_string::FieldCompressedString;
    // contract instance registry
    use contract_instance_registry::ContractInstanceRegistry;
    // nft note structs
    use crate::types::nft_note::{NFTNote, PartialNFTNote};

    /// @param symbol The symbol of the NFT
    /// @param name The name of the NFT
    /// @param private_nfts A map from address to a private set of NFTNotes owned by that address
    /// @param nft_exists A map from token ID to a boolean indicating if the NFT exists
    /// @param public_owners A map from token ID to the public owner of the NFT
    /// @param minter The address that can mint
    /// @param upgrade_authority The address that can upgrade the contract
    #[storage]
    struct Storage<Context> {
        symbol: PublicImmutable<FieldCompressedString, Context>,
        name: PublicImmutable<FieldCompressedString, Context>,
        private_nfts: Owned<PrivateSet<NFTNote, Context>, Context>,
        nft_exists: Map<Field, PublicMutable<bool, Context>, Context>,
        public_owners: Map<Field, PublicMutable<AztecAddress, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
        upgrade_authority: PublicImmutable<AztecAddress, Context>,
    }

    /// @dev Initializes the token with a minter
    /// @param name The name of the NFT
    /// @param symbol The symbol of the NFT
    /// @param minter The address of the minter
    /// @param upgrade_authority The address of the upgrade authority
    #[external("public")]
    #[initializer]
    fn constructor_with_minter(
        name: str<31>,
        symbol: str<31>,
        minter: AztecAddress,
        upgrade_authority: AztecAddress,
    ) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.minter.initialize(minter);
        self.storage.upgrade_authority.initialize(upgrade_authority);
    }

    /** ==========================================================
     * ========================= PRIVATE =========================
     * ======================================================== */

    /// @notice Transfers token by id from private owner to a public owner
    /// @dev Removes token from private owner, and enqueues a public call to update the public owner
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The id of the token to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        self.internal._remove_private_token_owner(from, token_id);
        self.enqueue_self.update_public_token_owner_from_zero_internal(to, token_id);
    }

    /// @notice Transfers token by id from private owner to a public owner with a commitment
    /// @dev Removes token from private owner, enqueues a public call to update the public owner, and returns a commitment
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The id of the token to transfer
    /// @param _nonce The nonce used for authwitness
    /// @return commitment The partial nft note utilized for the transfer commitment (privacy entrance)
    #[external("private")]
    fn transfer_private_to_public_with_commitment(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) -> Field {
        _validate_from_private::<4>(self.context, from);

        self.internal._remove_private_token_owner(from, token_id);
        self.enqueue_self.update_public_token_owner_from_zero_internal(to, token_id);
        let completer = self.msg_sender();
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        commitment.commitment()
    }

    /// @notice Transfers token by id from private owner to another private owner
    /// @dev Removes token by id from private owner, and sends a nft note with id to the recipient
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The id of the token to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        self.internal._remove_private_token_owner(from, token_id);
        self.internal._update_private_token_owner(to, token_id);
    }

    /// @notice Transfers token by id from private owner to the recipient commitment (recipient must create a commitment first)
    /// @dev Removes token by id from private owner, and enqueues a public call to complete the commitment
    /// @param from The address of the sender
    /// @param token_id The id of the token to transfer
    /// @param commitment The commitment to use for the transfer
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        token_id: Field,
        commitment: Field,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        self.internal._remove_private_token_owner(from, token_id);
        let completer = from;
        self.enqueue_self.transfer_token_to_commitment_internal(
            commitment.to_field(),
            token_id,
            completer,
        );
    }

    /// @notice Transfers token by id from public owner to private owner
    /// @dev Enqueues a public call to remove the public owner, and emits a nft note with id to the recipient
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The id of the token to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        self.enqueue_self.update_public_token_owner_internal(from, AztecAddress::zero(), token_id);
        self.internal._update_private_token_owner(to, token_id);
    }

    /// @notice Initializes a transfer commitment to be used for transfers
    /// @dev Returns a partial nft note that can be used to execute transfers
    /// @param to The address of the recipient
    /// @param completer The address allowed to complete the partial note
    /// @return commitment The partial nft note utilized for the transfer commitment (privacy entrance)
    #[external("private")]
    fn initialize_transfer_commitment(to: AztecAddress, completer: AztecAddress) -> Field {
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        commitment.commitment()
    }

    /** ==========================================================
     * ========================= PUBLIC ==========================
     * ======================================================== */

    /// @notice Transfers a token from one public owner to another public owner
    /// @dev Public call that asserts that the caller is the token owner, and updates the public owner
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The id of the token to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn transfer_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        _validate_from_public(self.context, from);
        self.internal._validate_public_token_owner(from, token_id);

        self.internal._update_public_token_owner(to, token_id);
    }

    /// @notice Transfers a token to a commitment
    /// @dev Public call that asserts that the caller is the token owner, and updates the public owner, and completes the commitment
    /// @param from The address of the sender
    /// @param token_id The id of the token to transfer
    /// @param commitment The commitment to use for the transfer
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn transfer_public_to_commitment(
        from: AztecAddress,
        token_id: Field,
        commitment: Field,
        _nonce: Field,
    ) {
        _validate_from_public(self.context, from);
        self.internal._validate_public_token_owner(from, token_id);

        self.internal._update_public_token_owner(AztecAddress::zero(), token_id);
        let completer = self.msg_sender();
        self.internal._transfer_token_to_commitment(commitment.to_field(), token_id, completer);
    }

    /// @notice Stores a commitment in storage
    /// @param commitment The commitment to store
    #[external("public")]
    #[only_self]
    fn store_commitment_in_storage_internal(commitment: PartialNFTNote) {
        self.internal._store_commitment_in_storage(commitment);
    }

    /// @notice Transfers a token to a commitment
    /// @param commitment The commitment to transfer
    /// @param token_id The id of the token to transfer
    /// @param completer The address that is authorized to complete this commitment
    #[external("public")]
    #[only_self]
    fn transfer_token_to_commitment_internal(
        commitment: Field,
        token_id: Field,
        completer: AztecAddress,
    ) {
        self.internal._transfer_token_to_commitment(commitment, token_id, completer);
    }

    /// @notice Updates the public token owner
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The id of the token to update
    #[external("public")]
    #[only_self]
    fn update_public_token_owner_internal(from: AztecAddress, to: AztecAddress, token_id: Field) {
        self.internal._validate_public_token_owner(from, token_id);
        self.internal._update_public_token_owner(to, token_id);
    }

    /// @notice Initializes the public token owner from zero address
    /// @param to The address of the new owner
    /// @param token_id The id of the token to update
    #[external("public")]
    #[only_self]
    fn update_public_token_owner_from_zero_internal(to: AztecAddress, token_id: Field) {
        self.internal._update_public_token_owner(to, token_id);
    }

    /// @notice Sets the existence of a token
    /// @dev Asserts token does not exist when setting `exists` to true (minting) and that token exist when setting `exists` to false (burning)
    /// @param token_id The id of the token to set
    /// @param exists The new exists value
    #[external("public")]
    #[only_self]
    fn set_nft_exists_internal(token_id: Field, exists: bool) {
        if exists {
            assert(!self.storage.nft_exists.at(token_id).read(), "token already exists");
        } else {
            assert(self.storage.nft_exists.at(token_id).read(), "token does not exist");
        }
        self.storage.nft_exists.at(token_id).write(exists);
    }

    /** ==========================================================
     * ====================== VIEW FUNCTIONS =====================
     * ======================================================== */

    /// @return name The name of the NFT collection
    #[external("public")]
    #[view]
    fn public_get_name() -> pub FieldCompressedString {
        self.storage.name.read()
    }

    /// @return symbol The symbol of the NFT collection
    #[external("public")]
    #[view]
    fn public_get_symbol() -> pub FieldCompressedString {
        self.storage.symbol.read()
    }

    /// @return owner The owner of a token by id
    #[external("public")]
    #[view]
    fn public_owner_of(token_id: Field) -> pub AztecAddress {
        self.storage.public_owners.at(token_id).read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    /// @notice Returns an array of token IDs owned by `owner` in private and a flag indicating whether a page limit was reached
    /// @dev Starts getting the notes from page with index `page_index`
    /// @dev Zero values in the array are placeholder values for non-existing notes
    /// @param owner The address of the owner
    /// @param page_index The index of the page to start getting notes from
    /// @return owned_nft_ids An array of token IDs owned by `owner`
    /// @return page_limit_reached A flag indicating whether a page limit was reached
    #[external("utility")]
    unconstrained fn get_private_nfts(
        owner: AztecAddress,
        page_index: u32,
    ) -> pub ([Field; MAX_NOTES_PER_PAGE], bool) {
        let offset = page_index * MAX_NOTES_PER_PAGE;
        let mut options = NoteViewerOptions::new();
        let nfts = self.storage.private_nfts.at(owner).view_notes(options.set_offset(offset));
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

    /// @notice Mints a token to a private address
    /// @dev Asserts that the caller is an authorized minter
    /// @param to The address of the recipient
    /// @param token_id The id of the token to mint
    #[external("private")]
    fn mint_to_private(to: AztecAddress, token_id: Field) {
        assert(token_id != 0, "zero token ID not supported");
        _validate_minter(self.msg_sender(), self.storage.minter.read());

        self.enqueue_self.set_nft_exists_internal(token_id, true);
        self.storage.private_nfts.at(to).insert(NFTNote { token_id }).deliver(
            MessageDelivery.ONCHAIN_CONSTRAINED,
        );
    }

    /// @notice Mints a token to a public address
    /// @dev Asserts that the caller is an authorized minter
    /// @param to The address of the recipient
    /// @param token_id The id of the token to mint
    #[external("public")]
    fn mint_to_public(to: AztecAddress, token_id: Field) {
        assert(token_id != 0, "zero token ID not supported");
        _validate_minter(self.msg_sender(), self.storage.minter.read());
        assert(!self.storage.nft_exists.at(token_id).read(), "token already exists");

        self.storage.nft_exists.at(token_id).write(true);
        self.storage.public_owners.at(token_id).write(to);
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns a token from a private address
    /// @dev Asserts that the caller is token owner, removes private token owner, and enqueues a public call to burn token
    /// @param from The address of the owner
    /// @param token_id The id of the token to burn
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn burn_private(from: AztecAddress, token_id: Field, _nonce: Field) {
        _validate_from_private::<3>(self.context, from);

        self.internal._remove_private_token_owner(from, token_id);
        self.enqueue_self.set_nft_exists_internal(token_id, false);
    }

    /// @notice Burns a token from a public address
    /// @dev Asserts that token exists and that the caller is token owner, removes public token owner, and burns token
    /// @param from The address of the owner
    /// @param token_id The id of the token to burn
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn burn_public(from: AztecAddress, token_id: Field, _nonce: Field) {
        _validate_from_public(self.context, from);

        self.internal._validate_public_token_owner(from, token_id);
        self.internal._update_public_token_owner(AztecAddress::zero(), token_id);
        self.storage.nft_exists.at(token_id).write(false);
    }

    /** ==========================================================
     * ===================  UPGRADEABLE  =========================
     * ======================================================== */

    /// @notice Upgrades the contract to a new contract class id
    /// @dev The upgrade authority must be set
    /// @dev The upgrade will only be effective after the upgrade delay has passed
    /// @param new_contract_class_id The new contract class id
    #[external("public")]
    fn upgrade_contract(new_contract_class_id: Field) {
        let upgrade_authority = self.storage.upgrade_authority.read();

        assert(!upgrade_authority.eq(AztecAddress::zero()), "upgrade authority not set");
        assert(self.msg_sender().eq(upgrade_authority), "caller is not upgrade authority");

        self.call(ContractInstanceRegistry::at(CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS).update(
            ContractClassId::from_field(new_contract_class_id),
        ));
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// @notice Stores a commitment in storage
    /// @param commitment The commitment to store
    #[internal("public")]
    fn _store_commitment_in_storage(commitment: PartialNFTNote) {
        self.context.storage_write(commitment.commitment(), true);
    }

    /// @notice Initializes a transfer commitment
    /// @param to The address of the recipient
    /// @param completer The address that can complete the commitment
    /// @return commitment The partial nft note utilized for the transfer commitment (privacy entrance)
    #[internal("private")]
    fn _initialize_transfer_commitment(
        to: AztecAddress,
        completer: AztecAddress,
    ) -> PartialNFTNote {
        let commitment = NFTNote::partial(
            to,
            self.storage.private_nfts.get_storage_slot(),
            self.context,
            to,
            completer,
        );
        self.enqueue_self.store_commitment_in_storage_internal(commitment);
        commitment
    }

    /// @notice Updates the private token owner
    /// @param to The address of the recipient
    /// @param token_id The id of the token to update
    #[internal("private")]
    fn _update_private_token_owner(to: AztecAddress, token_id: Field) {
        let new_note = NFTNote { token_id };
        self.storage.private_nfts.at(to).insert(new_note).deliver(
            MessageDelivery.ONCHAIN_CONSTRAINED,
        );
    }

    /// @notice Removes the private token owner
    /// @param from The address of the owner
    /// @param token_id The id of the token to remove
    #[internal("private")]
    fn _remove_private_token_owner(from: AztecAddress, token_id: Field) {
        let notes = self.storage.private_nfts.at(from).pop_notes(NoteGetterOptions::new()
            .select(NFTNote::properties().token_id, Comparator.EQ, token_id)
            .set_limit(1));
        assert(notes.len() == 1, "nft not found in private to public");
    }

    /// @notice Updates the public token owner
    /// @param to The address of the recipient
    /// @param token_id The id of the token to update
    #[internal("public")]
    fn _update_public_token_owner(to: AztecAddress, token_id: Field) {
        self.storage.public_owners.at(token_id).write(to);
    }

    /// @notice Transfers a token to a commitment
    /// @dev Asserts that a commitment is valid, and completes it
    /// @param commitment The commitment to complete
    /// @param token_id The id of the token to transfer
    /// @param completer The address that is authorized to complete this commitment
    #[internal("public")]
    fn _transfer_token_to_commitment(commitment: Field, token_id: Field, completer: AztecAddress) {
        // We verify that the commitment we're completing is valid (i.e. it uses the correct state variable's storage
        // slot, and it is internally consistent). We *could* clear the storage since each commitment should only be
        // used once, but since the AVM offers no gas refunds for doing so this would just make the transaction be more
        // expensive.
        assert(self.context.storage_read(commitment), "invalid commitment");
        PartialNFTNote::new(commitment).complete(&mut self.context, completer, token_id);
    }

    /// @notice Validates that the caller is the owner of a token
    /// @param from The address of the sender
    /// @param token_id The id of the token to validate
    #[internal("public")]
    fn _validate_public_token_owner(from: AztecAddress, token_id: Field) {
        let owner = self.storage.public_owners.at(token_id).read();
        assert(owner.eq(from), "caller is not owner");
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
    fn _validate_from_private<let N: u32>(context: &mut PrivateContext, from: AztecAddress) {
        if (!from.eq(context.maybe_msg_sender().unwrap())) {
            assert_current_call_valid_authwit::<N>(context, from);
        }
    }

    /// @notice Validates that the caller possesses authwit from the `from` address or the caller is the `from` address
    /// @param context The context of the public call
    /// @param from The address of the sender
    #[contract_library_method]
    unconstrained fn _validate_from_public(context: PublicContext, from: AztecAddress) {
        if (!from.eq(context.maybe_msg_sender().unwrap())) {
            assert_current_call_valid_authwit_public(context, from);
        }
    }
}
