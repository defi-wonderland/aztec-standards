mod types;
mod test;

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
        protocol_types::{
            constants::DEPLOYER_CONTRACT_ADDRESS, contract_class_id::ContractClassId,
            traits::FromField,
        },
        utils::comparison::Comparator,
    };
    // compression library
    use compressed_string::FieldCompressedString;
    // contract instance deployer
    use contract_instance_deployer::ContractInstanceDeployer;
    // sft note struct
    use crate::types::sft_note::{PartialSFTNote, SFTNote};

    /// Storage layout for Semi-Fungible Token (SFT) contract
    /// @param name The name of the SFT collection
    /// @param symbol The symbol of the SFT collection
    /// @param minter The account permissioned to mint new tokens
    /// @param private_sfts Private SFT ownership using nested mapping (token_id -> address -> PrivateSet<SFTNote>)
    /// @param public_sfts Public SFT balances using nested mapping (token_id -> address -> u128 balance)
    /// @param token_type_exists Whether a token type exists
    /// @param total_supply Total supply of each token type
    /// @param upgrade_authority The address of the upgrade authority
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
        private_sfts: Map<Field, Map<AztecAddress, PrivateSet<SFTNote, Context>, Context>, Context>,
        public_sfts: Map<Field, Map<AztecAddress, PublicMutable<u128, Context>, Context>, Context>,
        total_supply: Map<Field, PublicMutable<u128, Context>, Context>,
        token_type_exists: Map<Field, PublicMutable<bool, Context>, Context>,
        upgrade_authority: PublicImmutable<AztecAddress, Context>,
    }

    /// @notice Initializes the SFT contract with a minter
    /// @param name The name of the SFT collection
    /// @param symbol The symbol of the SFT collection
    /// @param minter The address of the minter (zero address to disable minting)
    /// @param upgrade_authority The address of the upgrade authority
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
     * ========================= PRIVATE =========================
     * ======================================================== */

    /// @notice Transfers a token from private ownership to public ownership
    /// @dev Removes one SFTNote from private storage and enqueues a public call to add to public storage
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The ID of the token type
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        _validate_from_private(&mut context, from);

        _remove_private_token(storage.private_sfts.at(token_id).at(from), token_id);
        SFT::at(context.this_address()).increment_public_balance_internal(to, token_id).enqueue(
            &mut context,
        );
    }

    /// @notice Transfers a token from private to public ownership and returns a commitment
    /// @dev Removes one SFTNote from private storage, enqueues public call, and returns a commitment for privacy entrance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The ID of the token type
    /// @param _nonce The nonce used for authwitness
    /// @return commitment The partial SFT note utilized for the transfer commitment (privacy entrance)
    #[private]
    fn transfer_private_to_public_with_commitment(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) -> Field {
        _validate_from_private(&mut context, from);

        _remove_private_token(storage.private_sfts.at(token_id).at(from), token_id);
        SFT::at(context.this_address()).increment_public_balance_internal(to, token_id).enqueue(
            &mut context,
        );

        let completer = context.msg_sender();
        let commitment = _initialize_transfer_commitment(
            &mut context,
            storage.private_sfts,
            token_id,
            from,
            to,
            completer,
        );
        commitment.commitment()
    }

    /// @notice Transfers a token from one private owner to another private owner
    /// @dev Removes one SFTNote from sender's private storage and creates a new SFTNote for recipient
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The ID of the token type
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        _validate_from_private(&mut context, from);
        _remove_private_token(storage.private_sfts.at(token_id).at(from), token_id);
        _add_private_token(
            &mut context,
            storage.private_sfts.at(token_id).at(to),
            from,
            to,
            token_id,
        );
    }

    /// @notice Transfers a token from private ownership to an existing commitment
    /// @dev Removes one SFTNote from private storage and enqueues a public call to complete the commitment
    /// @param from The address of the sender
    /// @param token_id The ID of the token type
    /// @param commitment The existing commitment to complete
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        token_id: Field,
        commitment: Field,
        _nonce: Field,
    ) {
        _validate_from_private(&mut context, from);

        _remove_private_token(storage.private_sfts.at(token_id).at(from), token_id);
        let completer = from;
        SFT::at(context.this_address())
            .transfer_token_to_commitment_internal(
                PartialSFTNote { commitment },
                token_id,
                completer,
            )
            .enqueue(&mut context);
    }

    /// @notice Transfers a token from public ownership to private ownership
    /// @dev Enqueues a public call to remove from public storage and creates a new private SFTNote for recipient
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The ID of the token type
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        _validate_from_private(&mut context, from);

        SFT::at(context.this_address()).decrement_public_balance_internal(from, token_id).enqueue(
            &mut context,
        );
        _add_private_token(
            &mut context,
            storage.private_sfts.at(token_id).at(to),
            from,
            to,
            token_id,
        );
    }

    /// @notice Initializes a transfer commitment to be used for transfers
    /// @dev Returns a partial sft note that can be used to execute transfers
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param completer The address of the completer
    /// @return commitment The partial sft note utilized for the transfer commitment (privacy entrance)
    #[private]
    fn initialize_transfer_commitment(
        token_id: Field,
        from: AztecAddress,
        to: AztecAddress,
        completer: AztecAddress,
    ) -> Field {
        let commitment = _initialize_transfer_commitment(
            &mut context,
            storage.private_sfts,
            token_id,
            from,
            to,
            completer,
        );
        commitment.commitment()
    }

    /** ==========================================================
     * ========================= PUBLIC ==========================
     * ======================================================== */

    /// @notice Transfers a token from one public address to another public address
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The ID of the token type
    /// @param _nonce The nonce used for authwitness
    #[public]
    fn transfer_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        _validate_from_public(&mut context, from);
        _validate_public_balance(storage.public_sfts, from, token_id);

        _decrement_public_balance(storage.public_sfts, from, token_id);
        _increment_public_balance(storage.public_sfts, to, token_id);
    }

    /// @notice Transfers a token from public address to a commitment
    /// @param from The address of the sender
    /// @param token_id The ID of the token type
    /// @param commitment The commitment to transfer to
    /// @param _nonce The nonce used for authwitness
    #[public]
    fn transfer_public_to_commitment(
        from: AztecAddress,
        token_id: Field,
        commitment: Field,
        _nonce: Field,
    ) {
        _validate_from_public(&mut context, from);
        _validate_public_balance(storage.public_sfts, from, token_id);

        _decrement_public_balance(storage.public_sfts, from, token_id);
        let completer = context.msg_sender();
        _transfer_token_to_commitment(
            &mut context,
            PartialSFTNote { commitment },
            token_id,
            completer,
        );
    }

    /// @notice Stores a commitment in storage
    /// @param commitment The commitment to store
    #[public]
    #[internal]
    fn store_commitment_in_storage_internal(commitment: PartialSFTNote) {
        _store_commitment_in_storage(&mut context, commitment);
    }

    /// @notice Creates a new token type with a total supply of 0
    /// @param token_id The ID of the new token type
    #[public]
    fn create_token_type(token_id: Field) {
        _validate_minter(context.msg_sender(), storage.minter.read());
        assert(!storage.token_type_exists.at(token_id).read(), "token type already exists");
        _create_token_type_internal(storage.token_type_exists, token_id);
    }

    /// @notice Internal function to create a token type without minter validation
    /// @param token_id The ID of the new token type
    #[public]
    #[internal]
    fn create_token_type_internal(token_id: Field) {
        _create_token_type_internal(storage.token_type_exists, token_id);
    }

    /// @notice Increases the total supply of a token type
    /// @param token_id The ID of the token type
    #[public]
    #[internal]
    fn increment_total_supply_internal(token_id: Field) {
        _increment_total_supply(storage.total_supply, token_id);
    }

    /// @notice Decreases the total supply of a token type
    /// @param token_id The ID of the token type
    #[public]
    #[internal]
    fn decrement_total_supply_internal(token_id: Field) {
        _decrement_total_supply(storage.total_supply, token_id);
    }

    /// @notice Increases a user's public balance
    /// @param to The address of the recipient
    /// @param token_id The ID of the token type
    #[public]
    #[internal]
    fn increment_public_balance_internal(to: AztecAddress, token_id: Field) {
        _increment_public_balance(storage.public_sfts, to, token_id);
    }

    /// @notice Completes a commitment with token details
    /// @param commitment The partial note representing the commitment
    /// @param token_id The ID of the token type
    /// @param completer The address authorized to complete this commitment
    #[public]
    #[internal]
    fn transfer_token_to_commitment_internal(
        commitment: PartialSFTNote,
        token_id: Field,
        completer: AztecAddress,
    ) {
        _transfer_token_to_commitment(&mut context, commitment, token_id, completer);
    }

    /// @notice Decreases a user's public balance
    /// @param from The address of the owner
    /// @param token_id The ID of the token type
    #[public]
    #[internal]
    fn decrement_public_balance_internal(from: AztecAddress, token_id: Field) {
        _decrement_public_balance(storage.public_sfts, from, token_id);
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

    /// @param token_id The ID of the token type
    /// @return Whether a token type exists
    #[public]
    #[view]
    fn public_token_type_exists(token_id: Field) -> bool {
        storage.token_type_exists.at(token_id).read()
    }

    /// @param owner The address of the owner
    /// @param token_id The ID of the token type
    /// @return The balance of the public balance of `owner` for `token_id`
    #[public]
    #[view]
    fn balance_of_public_by_token_id(owner: AztecAddress, token_id: Field) -> u128 {
        storage.public_sfts.at(token_id).at(owner).read()
    }

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
    pub unconstrained fn balance_of_private_by_token_id(
        owner: AztecAddress,
        token_id: Field,
        page_index: u32,
    ) -> u128 {
        let offset = page_index * MAX_NOTES_PER_PAGE;
        let mut options = NoteViewerOptions::new();
        let sfts =
            storage.private_sfts.at(token_id).at(owner).view_notes(options.set_offset(offset));
        sfts.len() as u128
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    /// @notice Mints a new token to the private collection
    /// @param to The address of the recipient
    /// @param token_id The ID of the token type
    #[private]
    fn mint_to_private(to: AztecAddress, token_id: Field) {
        assert(token_id != 0, "zero token ID not supported");
        _validate_minter(context.msg_sender(), storage.minter.read());

        storage.private_sfts.at(token_id).at(to).insert(SFTNote::new(token_id, to)).emit(
            encode_and_encrypt_note(&mut context, to, to),
        );

        SFT::at(context.this_address()).create_token_type_internal(token_id).enqueue(&mut context);
        SFT::at(context.this_address()).increment_total_supply_internal(token_id).enqueue(
            &mut context,
        );
    }

    /// @notice Mints a new token to the public collection
    /// @param to The address of the recipient
    /// @param token_id The ID of the token type
    #[public]
    fn mint_to_public(to: AztecAddress, token_id: Field) {
        assert(storage.token_type_exists.at(token_id).read(), "token type does not exist");
        _validate_minter(context.msg_sender(), storage.minter.read());
        _increment_total_supply(storage.total_supply, token_id);

        _increment_public_balance(storage.public_sfts, to, token_id);
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns a token from the private collection
    /// @param from The address of the owner
    /// @param token_id The ID of the token type
    /// @param _nonce The nonce of the burn
    #[private]
    fn burn_private(from: AztecAddress, token_id: Field, _nonce: Field) {
        _validate_from_private(&mut context, from);
        _remove_private_token(storage.private_sfts.at(token_id).at(from), token_id);

        SFT::at(context.this_address()).decrement_total_supply_internal(token_id).enqueue(
            &mut context,
        );
    }

    /// @notice Burns a token from the public collection
    /// @param from The address of the owner
    /// @param token_id The ID of the token type
    #[public]
    fn burn_public(from: AztecAddress, token_id: Field, _nonce: Field) {
        _validate_from_public(&mut context, from);
        _validate_public_balance(storage.public_sfts, from, token_id);
        _decrement_total_supply(storage.total_supply, token_id);
        _decrement_public_balance(storage.public_sfts, from, token_id);
    }

    /** ==========================================================
     * ===================  UPGRADEABLE  =========================
     * ======================================================== */

    /// @notice Upgrades the contract to a new contract class id
    /// @dev The upgrade authority must be set
    /// @dev The upgrade will only be effective after the upgrade delay has passed
    /// @param new_contract_class_id The new contract class id
    #[public]
    fn upgrade_contract(new_contract_class_id: Field) {
        let upgrade_authority = storage.upgrade_authority.read();

        assert(!upgrade_authority.eq(AztecAddress::zero()), "upgrade authority not set");
        assert(context.msg_sender().eq(upgrade_authority), "caller is not upgrade authority");

        ContractInstanceDeployer::at(DEPLOYER_CONTRACT_ADDRESS)
            .update(ContractClassId::from_field(new_contract_class_id))
            .call(&mut context);
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// @notice Internal helper to create a token type without minter validation
    /// @param token_type_exists The storage pointer to the token type existence map
    /// @param token_id The ID of the new token type
    #[contract_library_method]
    fn _create_token_type_internal(
        token_type_exists: Map<Field, PublicMutable<bool, &mut PublicContext>, &mut PublicContext>,
        token_id: Field,
    ) {
        token_type_exists.at(token_id).write(true);
    }

    /// @notice Stores a commitment in storage
    /// @param context The context of the public call
    /// @param commitment The commitment to store
    #[contract_library_method]
    fn _store_commitment_in_storage(context: &mut PublicContext, commitment: PartialSFTNote) {
        context.storage_write(commitment.commitment(), true);
    }

    /// @notice Initializes a transfer commitment
    /// @param context The context of the private call
    /// @param private_sfts The private owner
    /// @param token_id The ID of the token type
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param completer The address that can complete the commitment
    /// @return commitment The partial sft note utilized for the transfer commitment (privacy entrance)
    #[contract_library_method]
    fn _initialize_transfer_commitment(
        context: &mut PrivateContext,
        private_sfts: Map<Field, Map<AztecAddress, PrivateSet<SFTNote, &mut PrivateContext>, &mut PrivateContext>, &mut PrivateContext>,
        token_id: Field,
        from: AztecAddress,
        to: AztecAddress,
        completer: AztecAddress,
    ) -> PartialSFTNote {
        let commitment = SFTNote::partial(
            to,
            private_sfts.at(token_id).at(to).storage_slot,
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

    /// @notice Adds a private token to the recipient
    /// @param context The context of the private call
    /// @param private_sft_set The private set to add to
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The ID of the token type
    #[contract_library_method]
    fn _add_private_token(
        context: &mut PrivateContext,
        private_sft_set: PrivateSet<SFTNote, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
    ) {
        let new_note = SFTNote::new(token_id, to);
        private_sft_set.insert(new_note).emit(encode_and_encrypt_note(context, to, from));
    }

    /// @notice Removes a private token
    /// @param private_sft_set The private set to remove from
    /// @param token_id The ID of the token type
    #[contract_library_method]
    fn _remove_private_token(
        private_sft_set: PrivateSet<SFTNote, &mut PrivateContext>,
        token_id: Field,
    ) {
        let notes = private_sft_set.pop_notes(NoteGetterOptions::new()
            .select(SFTNote::properties().token_id, Comparator.EQ, token_id)
            .set_limit(1));
        assert(notes.len() == 1, "sft not found in private");
    }

    /// @notice Increases the total supply of a token type
    /// @param total_supply The storage pointer to the total supply
    /// @param token_id The ID of the token type
    #[contract_library_method]
    fn _increment_total_supply(
        total_supply: Map<Field, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        token_id: Field,
    ) {
        total_supply.at(token_id).write(total_supply.at(token_id).read() + 1);
    }

    /// @notice Decreases the total supply of a token type
    /// @param total_supply The storage pointer to the total supply
    /// @param token_id The ID of the token type
    #[contract_library_method]
    fn _decrement_total_supply(
        total_supply: Map<Field, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        token_id: Field,
    ) {
        total_supply.at(token_id).write(total_supply.at(token_id).read() - 1);
    }

    /// @notice Increases a user's public balance for a specific token type
    /// @param public_sfts The storage pointer to the public balances
    /// @param to The address of the recipient
    /// @param token_id The ID of the token type
    #[contract_library_method]
    fn _increment_public_balance(
        public_sfts: Map<Field, Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>, &mut PublicContext>,
        to: AztecAddress,
        token_id: Field,
    ) {
        let current_balance = public_sfts.at(token_id).at(to).read();
        public_sfts.at(token_id).at(to).write(current_balance + 1);
    }

    /// @notice Decreases a user's public balance for a specific token type
    /// @param public_sfts The storage pointer to the public balances
    /// @param from The address of the owner
    /// @param token_id The ID of the token type
    #[contract_library_method]
    fn _decrement_public_balance(
        public_sfts: Map<Field, Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        token_id: Field,
    ) {
        let current_balance = public_sfts.at(token_id).at(from).read();
        assert(current_balance > 0, "insufficient public balance");
        public_sfts.at(token_id).at(from).write(current_balance - 1);
    }

    /// @notice Transfers a token to a commitment
    /// @dev Asserts that a commitment is valid, and completes it
    /// @param context The context of the public call
    /// @param commitment The commitment to complete
    /// @param token_id The id of the token to transfer
    /// @param completer The address that is authorized to complete this commitment
    #[contract_library_method]
    fn _transfer_token_to_commitment(
        context: &mut PublicContext,
        commitment: PartialSFTNote,
        token_id: Field,
        completer: AztecAddress,
    ) {
        // assert(
        //     context.nullifier_exists(commitment.commitment(), context.this_address()),
        //     "invalid commitment",
        // );
        // TODO: should we use nullifier_exists check?
        assert(context.storage_read(commitment.commitment()), "invalid commitment");
        commitment.complete(context, completer, token_id);
    }

    /// @notice Validates that the caller has a positive balance of a token
    /// @param public_sfts The public balances map
    /// @param from The address of the sender
    /// @param token_id The id of the token to validate
    #[contract_library_method]
    fn _validate_public_balance(
        public_sfts: Map<Field, Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        token_id: Field,
    ) {
        let balance = public_sfts.at(token_id).at(from).read();
        assert(balance > 0, "caller owns no tokens of this type");
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
