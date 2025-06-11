pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract Token {
    // aztec library
    use aztec::{
        context::PrivateContext,
        macros::{
            functions::{initializer, internal, private, public, utility, view},
            storage::storage,
        },
        prelude::{AztecAddress, Map, PublicContext, PublicImmutable, PublicMutable},
        protocol_types::{
            constants::DEPLOYER_CONTRACT_ADDRESS,
            contract_class_id::ContractClassId,
            traits::{FromField, ToField},
        },
    };
    // authorized witness library
    use authwit::auth::{
        assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
    };
    // note library
    use uint_note::uint_note::{PartialUintNote, UintNote};
    // compression library
    use compressed_string::FieldCompressedString;
    // encryption library
    use aztec::messages::logs::note::encode_and_encrypt_note;
    // balance library
    use balance_set::balance_set::BalanceSet;

    // contract instance deployer
    use contract_instance_deployer::ContractInstanceDeployer;

    // gas-optimized max notes for initial transfer call
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    // max notes transfer for recursive transfer call if initial max notes are exceeded
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param private_balances The private balances of the token
    /// @param total_supply The total supply of the token
    /// @param public_balances The public balances of the token
    /// @param minter The account permissioned to mint the token
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<u128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
        upgrade_authority: PublicImmutable<AztecAddress, Context>,
    }

    /// @notice Initializes the token with an initial supply
    /// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param initial_supply The initial supply of the token
    /// @param to The address to mint the initial supply to
    /// @param upgrade_authority The address of the upgrade authority (zero address if not upgradeable)
    #[public]
    #[initializer]
    fn constructor_with_initial_supply(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        initial_supply: u128,
        to: AztecAddress,
        upgrade_authority: AztecAddress,
    ) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.decimals.initialize(decimals);

        _increase_public_balance(storage.public_balances, to, initial_supply);
        _increase_total_supply(storage.total_supply, initial_supply);

        storage.upgrade_authority.initialize(upgrade_authority);
    }

    /// @notice Initializes the token with a minter
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param minter The address of the minter
    /// @param upgrade_authority The address of the upgrade authority (zero address if not upgradeable)
    #[public]
    #[initializer]
    fn constructor_with_minter(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        minter: AztecAddress,
        upgrade_authority: AztecAddress,
    ) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.decimals.initialize(decimals);

        storage.minter.initialize(minter);
        storage.upgrade_authority.initialize(upgrade_authority);
    }

    /** ==========================================================
    * ========================= PRIVATE =========================
    * ======================================================== */

    /// @notice Transfer tokens from private balance to public balance
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private(&mut context, from);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        Token::at(context.this_address()).increase_public_balance_internal(to, amount).enqueue(
            &mut context,
        );
    }

    /// @notice Transfer tokens from private balance to public balance and initializes a commitment
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, enqueues a public call, and returns a partial note.
    ///      `to` will also be the completer of the initialized partial note.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    /// @return commitment The partial note utilized for the transfer commitment (privacy entrance)
    #[private]
    fn transfer_private_to_public_with_commitment(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) -> Field {
        _validate_from_private(&mut context, from);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        Token::at(context.this_address()).increase_public_balance_internal(to, amount).enqueue(
            &mut context,
        );

        // We're creating a commitment for the recipient, so the completer is the recipient
        let completer = to;
        let commitment = _initialize_transfer_commitment(
            &mut context,
            storage.private_balances,
            from,
            to,
            completer,
        );
        commitment.commitment
    }

    /// @notice Transfer tokens from private balance to another private balance
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and sends a note to the recipient
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private(&mut context, from);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        _increase_private_balance(&mut context, storage.private_balances, from, to, amount);
    }

    /// @notice Transfer tokens from private balance to the recipient's commitment (recipient must create a commitment first)
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
    ///      `from` will also be the completer of the partial note
    /// @param from The address of the sender
    /// @param commitment The partial note representing the commitment (privacy entrance that the recipient shares with the sender)
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private(&mut context, from);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        Token::at(context.this_address())
            .increase_commitment_balance_internal(PartialUintNote { commitment }, from, amount)
            .enqueue(&mut context);
    }

    /// @notice Transfer tokens from public balance to private balance
    /// @dev Enqueues a public call to decrease account balance and emits a new note with balance difference
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private(&mut context, from);

        Token::at(context.this_address()).decrease_public_balance_internal(from, amount).enqueue(
            &mut context,
        );

        _increase_private_balance(&mut context, storage.private_balances, from, to, amount);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @dev Returns a partial note that can be used to execute transfers/mints
    ///      `from` will also be the completer of the partial note.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @return commitment The partial note initialized for the transfer/mint commitment
    #[private]
    fn initialize_transfer_commitment(from: AztecAddress, to: AztecAddress) -> Field {
        let commitment =
            _initialize_transfer_commitment(&mut context, storage.private_balances, from, to, from);
        commitment.commitment
    }

    /// @notice Recursively subtracts balance from commitment
    /// @dev Used to subtract balances that exceed the max notes limit
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @return The change to return to the owner
    #[private]
    #[internal]
    fn recurse_subtract_balance_internal(account: AztecAddress, amount: u128) -> u128 {
        _subtract_balance(
            &mut context,
            storage.private_balances,
            account,
            amount,
            RECURSIVE_TRANSFER_CALL_MAX_NOTES,
        )
    }

    /** ==========================================================
    * ========================= PUBLIC ==========================
    * ======================================================== */

    /// @notice Transfers tokens from public balance to public balance
    /// @dev Public call to decrease account balance and a public call to increase recipient balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[public]
    fn transfer_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_public(&mut context, from);

        _decrease_public_balance(storage.public_balances, from, amount);
        _increase_public_balance(storage.public_balances, to, amount);
    }

    /// @notice Finalizes a transfer of token `amount` from public balance of `from` to a commitment of `to`
    /// @dev The transfer must be prepared by calling `initialize_transfer_commitment` first and the resulting
    /// `commitment` must be passed as an argument to this function.
    /// `from` will be used as the completer for the partial note.
    /// @param from The address of the sender
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[public]
    fn transfer_public_to_commitment(
        from: AztecAddress,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_public(&mut context, from);

        _decrease_public_balance(storage.public_balances, from, amount);

        _increase_commitment_balance(&mut context, PartialUintNote { commitment }, from, amount);
    }

    /// @notice Increases the public balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[public]
    #[internal]
    fn increase_public_balance_internal(to: AztecAddress, amount: u128) {
        _increase_public_balance(storage.public_balances, to, amount);
    }

    /// @notice Decreases the public balance of `from` by `amount`
    /// @param from The address of the sender
    /// @param amount The amount of tokens to decrease the balance by
    #[public]
    #[internal]
    fn decrease_public_balance_internal(from: AztecAddress, amount: u128) {
        _decrease_public_balance(storage.public_balances, from, amount);
    }

    /// @notice Increases the balance of the commitment by `amount`
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param amount The amount of tokens to increase the balance by
    #[public]
    #[internal]
    fn increase_commitment_balance_internal(
        commitment: PartialUintNote,
        completer: AztecAddress,
        amount: u128,
    ) {
        _increase_commitment_balance(&mut context, commitment, completer, amount);
    }

    /** ==========================================================
    * ====================== VIEW FUNCTIONS =====================
    * ======================================================== */

    /// @notice Returns the public balance of `owner`
    /// @param owner The address of the owner
    /// @return The balance of the public balance of `owner`
    #[public]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> u128 {
        storage.public_balances.at(owner).read()
    }

    /// @notice Returns the total supply of the token
    /// @return The total supply of the token
    #[public]
    #[view]
    fn total_supply() -> u128 {
        storage.total_supply.read()
    }

    /// @notice Returns the name of the token
    /// @return The name of the token
    #[public]
    #[view]
    fn name() -> FieldCompressedString {
        storage.name.read()
    }

    /// @notice Returns the symbol of the token
    /// @return The symbol of the token
    #[public]
    #[view]
    fn symbol() -> FieldCompressedString {
        storage.symbol.read()
    }

    /// @notice Returns the decimals of the token
    /// @return The decimals of the token
    #[public]
    #[view]
    fn decimals() -> u8 {
        storage.decimals.read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */
    #[utility]
    pub unconstrained fn balance_of_private(owner: AztecAddress) -> u128 {
        storage.private_balances.at(owner).balance_of()
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    /// @notice Mints tokens to a commitment
    /// @dev Mints tokens to a commitment and enqueues a public call to increase the total supply
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[private]
    fn mint_to_private(from: AztecAddress, to: AztecAddress, amount: u128) {
        _validate_minter(context.msg_sender(), storage.minter.read());

        _increase_private_balance(&mut context, storage.private_balances, from, to, amount);

        // Enqueue call to increase total supply
        Token::at(context.this_address()).increase_total_supply_internal(amount).enqueue(
            &mut context,
        );
    }

    /// @notice Mints tokens to a public balance
    /// @dev Increases the public balance of `to` by `amount` and the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[public]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        _validate_minter(context.msg_sender(), storage.minter.read());

        _increase_public_balance(storage.public_balances, to, amount);
        _increase_total_supply(storage.total_supply, amount);
    }

    /// @notice Finalizes a mint to a commitment
    /// @dev Finalizes a mint to a commitment and updates the total supply
    /// @param commitment The partial note representing the mint commitment (privacy entrance)
    /// @param amount The amount of tokens to mint
    #[public]
    fn mint_to_commitment(commitment: Field, amount: u128) {
        let sender = context.msg_sender();
        _validate_minter(sender, storage.minter.read());
        let completer = sender;
        _increase_total_supply(storage.total_supply, amount);
        _increase_commitment_balance(
            &mut context,
            PartialUintNote { commitment },
            completer,
            amount,
        );
    }

    #[public]
    #[internal]
    fn increase_total_supply_internal(amount: u128) {
        _increase_total_supply(storage.total_supply, amount);
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns tokens from a commitment
    /// @dev Burns tokens from a commitment and enqueues a public call to update the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn burn_private(from: AztecAddress, amount: u128, _nonce: Field) {
        _validate_from_private(&mut context, from);

        _decrease_private_balance(
            &mut context,
            storage.private_balances,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );

        Token::at(context.this_address()).decrease_total_supply_internal(amount).enqueue(
            &mut context,
        );
    }

    /// @notice Burns tokens from a public balance
    /// @dev Burns tokens from a public balance and updates the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[public]
    fn burn_public(from: AztecAddress, amount: u128, _nonce: Field) {
        _validate_from_public(&mut context, from);

        _decrease_public_balance(storage.public_balances, from, amount);
        _decrease_total_supply(storage.total_supply, amount);
    }

    /// @notice Decreases the total supply by `amount`
    /// @param amount The amount of tokens to decrease the total supply by
    #[public]
    #[internal]
    fn decrease_total_supply_internal(amount: u128) {
        _decrease_total_supply(storage.total_supply, amount);
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// Validates that the caller is the minter
    #[contract_library_method]
    fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }

    /// Decreases the private balance of `account` by `amount` and emits a private balance note with the change to account
    #[contract_library_method]
    fn _decrease_private_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: u128,
        max_notes: u32,
    ) {
        // Subtracts `amount` from the private balance of `account`
        let change = _subtract_balance(context, private_balances, account, amount, max_notes);
        // Increases `change` to the private balance of `account`, and emits a private balance note to account
        private_balances.at(account).add(account, change).emit(encode_and_encrypt_note(
            context,
            account,
            account,
        ));
    }

    /// @notice Updates the given storage pointer `private_balances` to increase the private balance of `to` by `amount`
    /// @param private_balances The storage pointer to the private balances
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[contract_library_method]
    fn _increase_private_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
    ) {
        // Increases `amount` to the private balance of `to`, and emits a private balance note to `to` from `from`
        private_balances.at(to).add(to, amount).emit(encode_and_encrypt_note(context, to, from));
    }

    /// @notice Updates the given storage pointer `public_balances` to increase the public balance of `to` by `amount`
    /// @param public_balances The storage pointer to the public balances
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[contract_library_method]
    fn _increase_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        to: AztecAddress,
        amount: u128,
    ) {
        // Read the current public balance of `to`, add `amount` to it,
        let new_balance = public_balances.at(to).read() + amount;
        // write the result back to the storage
        public_balances.at(to).write(new_balance);
    }

    /// @notice Updates the given storage pointer `public_balances` to decrease the public balance of `from` by `amount`
    /// @param public_balances The storage pointer to the public balances
    /// @param from The address of the account to decrease the balance of
    /// @param amount The amount of tokens to decrease the balance by
    #[contract_library_method]
    fn _decrease_public_balance(
        public_balances: Map<AztecAddress, PublicMutable<u128, &mut PublicContext>, &mut PublicContext>,
        from: AztecAddress,
        amount: u128,
    ) {
        // read the current public balance of `from`, subtract `amount`
        let new_balance = public_balances.at(from).read() - amount;
        // update the public balance of `from` with the new balance
        public_balances.at(from).write(new_balance);
    }

    /// @notice Completes a partial note
    /// @dev Completes a partial note  and increases the balance of the commitment by `amount`
    /// @param context The context of the public call
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param completer The address used to compute the validity commitment
    /// @param amount The amount of tokens to increase the balance of the commitment by
    #[contract_library_method]
    fn _increase_commitment_balance(
        context: &mut PublicContext,
        commitment: PartialUintNote,
        completer: AztecAddress,
        amount: u128,
    ) {
        let validity_commitment = commitment.compute_validity_commitment(completer);
        commitment.complete(context, completer, amount);
    }

    /// @notice Subtracts balance from commitment
    /// @dev Subtracts amount from commitment and returns the change to the owner, recursively if necessary
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @return The change to return to the owner
    #[contract_library_method]
    fn _subtract_balance(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        account: AztecAddress,
        amount: u128,
        max_notes: u32,
    ) -> u128 {
        let subtracted = private_balances.at(account).try_sub(amount, max_notes);
        // Failing to subtract any amount means that the owner was unable to produce more notes that could be nullified.
        assert(subtracted > 0, "Balance too low");
        if subtracted >= amount {
            // We have achieved our goal of nullifying notes that add up to more than amount, so we return the change.
            subtracted - amount
        } else {
            // try_sub failed to nullify enough notes to reach the target amount, so we compute the amount remaining
            // and try again.
            let remaining = amount - subtracted;

            Token::at(context.this_address())
                .recurse_subtract_balance_internal(account, remaining)
                .call(context)
        }
    }

    /// @notice Increases the given storage pointer `total_supply` by `amount`
    /// @param total_supply The storage pointer to the total supply
    /// @param amount The amount of tokens to increase the total supply by
    #[contract_library_method]
    fn _increase_total_supply(total_supply: PublicMutable<u128, &mut PublicContext>, amount: u128) {
        let new_supply = total_supply.read() + amount;
        total_supply.write(new_supply);
    }

    /// @notice Decreases the given storage pointer `total_supply` by `amount`
    /// @param total_supply The storage pointer to the total supply
    /// @param amount The amount to decrease the total supply by
    #[contract_library_method]
    fn _decrease_total_supply(total_supply: PublicMutable<u128, &mut PublicContext>, amount: u128) {
        let new_supply = total_supply.read() - amount;
        total_supply.write(new_supply);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @param context The context of the private call
    /// @param private_balances The storage pointer to the private balances
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param completer The address used to compute the validity commitment
    /// @return The partial note that can be used to execute the transfer/mint
    #[contract_library_method]
    fn _initialize_transfer_commitment(
        context: &mut PrivateContext,
        private_balances: Map<AztecAddress, BalanceSet<&mut PrivateContext>, &mut PrivateContext>,
        from: AztecAddress,
        to: AztecAddress,
        completer: AztecAddress,
    ) -> PartialUintNote {
        let commitment = UintNote::partial(
            to,
            private_balances.at(to).set.storage_slot,
            context,
            to,
            from,
            completer,
        );

        commitment
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
