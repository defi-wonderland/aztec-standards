pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract Token {
    // aztec library
    use aztec::{
        authwit::auth::{
            assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
        },
        context::PrivateContext,
        macros::{
            events::event,
            functions::{external, initializer, internal, only_self, view},
            storage::storage,
        },
        messages::message_delivery::MessageDelivery,
        protocol::{
            address::AztecAddress,
            constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            contract_class_id::ContractClassId,
            traits::{FromField, ToField},
        },
        state_vars::{Map, Owned, PublicImmutable, PublicMutable, StateVariable},
    };
    // note library
    use uint_note::{PartialUintNote, UintNote};
    // compression library
    use compressed_string::FieldCompressedString;
    // contract instance registry
    use contract_instance_registry::ContractInstanceRegistry;
    // private balance library
    use balance_set::BalanceSet;

    // gas-optimized max notes for initial transfer call
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    // max notes transfer for recursive transfer call if initial max notes are exceeded
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    // Rounding direction that the vault uses to calculate shares and assets
    global ROUND_DOWN: bool = false;
    global ROUND_UP: bool = true;

    // Maximum value for a u128 (2**128 - 1)
    global MAX_U128_VALUE: u128 = 340282366920938463463374607431768211455;

    // Sentinel address used in Transfer events to represent the private side of a balance change.
    // sha224sum 'PRIVATE_ADDRESS'
    global PRIVATE_ADDRESS_MAGIC_VALUE: AztecAddress =
        AztecAddress::from_field(0x1ea7e01501975545617c2e694d931cb576b691a4a867fed81ebd3264);

    #[event]
    struct Transfer {
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
    }

    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param private_balances The private balances of the token
    /// @param total_supply The total supply of the token
    /// @param public_balances The public balances of the token
    /// @param minter The account permissioned to mint the token
    /// @param upgrade_authority The address with permission to upgrade the contract
    /// @param asset The underlying asset for yield-bearing vault functionality
    /// @param vault_offset The offset used to prevent inflation attacks
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Owned<BalanceSet<Context>, Context>,
        total_supply: PublicMutable<u128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
        upgrade_authority: PublicImmutable<AztecAddress, Context>,
        asset: PublicImmutable<AztecAddress, Context>,
        vault_offset: PublicImmutable<u128, Context>,
    }

    /// @notice Initializes the token with an asset
    /// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param asset The underlying asset for the yield bearing token
    /// @param vault_offset The offset used to prevent inflation attacks (typically 1)
    /// @param upgrade_authority The address of the upgrade authority (zero address if not upgradeable)
    #[external("public")]
    #[initializer]
    fn constructor_with_asset(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        asset: AztecAddress,
        vault_offset: u128,
        upgrade_authority: AztecAddress,
    ) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.decimals.initialize(decimals);
        self.storage.asset.initialize(asset);
        self.storage.vault_offset.initialize(vault_offset);

        self.storage.upgrade_authority.initialize(upgrade_authority);
    }

    /// @notice Initializes the token with an asset and an initial deposit
    /// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
    /// @dev The depositor is the address that will be used to sign the authwit for the transfer of the initial deposit
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param asset The underlying asset for the yield bearing token
    /// @param vault_offset The offset used to prevent inflation attacks (typically 1)
    /// @param upgrade_authority The address of the upgrade authority (zero address if not upgradeable)
    /// @param initial_deposit The initial deposit amount of the asset
    /// @param depositor The address of the initial depositor of the assets
    /// @param _nonce The nonce used for authwitness for the transfer of the initial deposit
    #[external("public")]
    #[initializer]
    fn constructor_with_asset_initial_deposit(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        asset: AztecAddress,
        vault_offset: u128,
        upgrade_authority: AztecAddress,
        initial_deposit: u128,
        depositor: AztecAddress,
        _nonce: Field,
    ) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.decimals.initialize(decimals);
        self.storage.asset.initialize(asset);
        self.storage.vault_offset.initialize(vault_offset);
        self.storage.upgrade_authority.initialize(upgrade_authority);

        // Caller deposits assets, shares are minted to this contract and are permanently locked.
        let from = depositor;
        let to = self.address;

        // Assets could be donated to the vault's precomputed address before deployment, but such assets are
        // ignored at this point to ensure the asset<>share conversion is 1:1 for the initial deposit.
        let total_assets = 0;

        // Calculate shares to mint for the initial deposit.
        let shares = self.internal._convert_to_shares(initial_deposit, total_assets, ROUND_DOWN);

        // Transfer the assets from the sender to the vault
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            to,
            initial_deposit,
            _nonce,
        ));

        // Mint shares to this contract address
        self.internal._mint_to_public(to, shares);
    }

    /// @notice Initializes the token with an initial supply
    /// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param initial_supply The initial supply of the token
    /// @param to The address to mint the initial supply to
    /// @param upgrade_authority The address of the upgrade authority (zero address if not upgradeable)
    #[external("public")]
    #[initializer]
    fn constructor_with_initial_supply(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        initial_supply: u128,
        to: AztecAddress,
        upgrade_authority: AztecAddress,
    ) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.decimals.initialize(decimals);

        self.internal._mint_to_public(to, initial_supply);

        self.storage.upgrade_authority.initialize(upgrade_authority);
    }

    /// @notice Initializes the token with a minter
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param minter The address of the minter
    /// @param upgrade_authority The address of the upgrade authority (zero address if not upgradeable)
    #[external("public")]
    #[initializer]
    fn constructor_with_minter(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        minter: AztecAddress,
        upgrade_authority: AztecAddress,
    ) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.decimals.initialize(decimals);

        self.storage.minter.initialize(minter);
        self.storage.upgrade_authority.initialize(upgrade_authority);
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
    #[external("private")]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        self.enqueue_self.increase_public_balance_internal(to, amount);
    }

    /// @notice Transfer tokens from private balance to public balance and initializes a commitment
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, enqueues a public call, and returns a partial note.
    ///      The sender will be used as the completer for the initialized partial note.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    /// @return commitment The partial note utilized for the transfer commitment (privacy entrance)
    #[external("private")]
    fn transfer_private_to_public_with_commitment(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) -> Field {
        _validate_from_private::<4>(self.context, from);

        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        self.enqueue_self.increase_public_balance_internal(to, amount);

        // Only the sender will be able to complete the partial note
        let completer = self.msg_sender();
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        commitment.to_field()
    }

    /// @notice Transfer tokens from private balance to another private balance
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and sends a note to the recipient
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        self.internal._increase_private_balance(to, amount);
    }

    /// @notice Transfer tokens from a private balance to the recipient commitment, which must be already initialized.
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call.
    ///      The `msg_sender` must be the completer of the partial note.
    /// @param from The address of the sender
    /// @param commitment The partial note representing the commitment (privacy entrance that the recipient shares with the sender)
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);

        let completer = self.msg_sender();
        PartialUintNote::from_field(commitment).complete_from_private(
            self.context,
            completer,
            amount,
        );
    }

    /// @notice Transfer tokens from public balance to private balance
    /// @dev Enqueues a public call to decrease account balance and emits a new note with balance difference
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        self.enqueue_self.decrease_public_balance_internal(from, amount);

        self.internal._increase_private_balance(to, amount);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @dev Returns a partial note that can be used to execute transfers/mints
    /// @param to The address of the recipient
    /// @param completer The address allowed to complete the partial note
    /// @return commitment The partial note initialized for the transfer/mint commitment
    #[external("private")]
    fn initialize_transfer_commitment(to: AztecAddress, completer: AztecAddress) -> Field {
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        commitment.to_field()
    }

    /// @notice Recursively subtracts balance from private balance
    /// @dev Used to subtract private balances that exceed the max notes limit
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @return The change to return to the owner
    #[external("private")]
    #[only_self]
    fn recurse_subtract_balance_internal(account: AztecAddress, amount: u128) -> u128 {
        self.internal._subtract_balance(account, amount, RECURSIVE_TRANSFER_CALL_MAX_NOTES)
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
    #[external("public")]
    fn transfer_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._validate_from_public(from);

        self.internal._decrease_public_balance(from, amount);
        self.internal._increase_public_balance(to, amount);

        self.emit(Transfer { from, to, amount });
    }

    /// @notice Finalizes a transfer of token `amount` from public balance of `from` to a commitment of `to`
    /// @dev The transfer must be prepared by calling `initialize_transfer_commitment` first and the resulting
    /// `commitment` must be passed as an argument to this function.
    /// @dev The sender will be used as the completer for the partial note.
    /// @param from The address of the sender
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param amount The amount of tokens to transfer
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn transfer_public_to_commitment(
        from: AztecAddress,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._validate_from_public(from);

        self.internal._decrease_public_balance(from, amount);

        let completer = self.msg_sender();
        self.internal._increase_commitment_balance(
            PartialUintNote::from_field(commitment),
            completer,
            amount,
        );

        self.emit(Transfer { from, to: PRIVATE_ADDRESS_MAGIC_VALUE, amount });
    }

    /// @notice Increases the public balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[external("public")]
    #[only_self]
    fn increase_public_balance_internal(to: AztecAddress, amount: u128) {
        self.internal._increase_public_balance(to, amount);

        self.emit(Transfer { from: PRIVATE_ADDRESS_MAGIC_VALUE, to, amount });
    }

    /// @notice Decreases the public balance of `from` by `amount`
    /// @param from The address of the sender
    /// @param amount The amount of tokens to decrease the balance by
    #[external("public")]
    #[only_self]
    fn decrease_public_balance_internal(from: AztecAddress, amount: u128) {
        self.internal._decrease_public_balance(from, amount);

        self.emit(Transfer { from, to: PRIVATE_ADDRESS_MAGIC_VALUE, amount });
    }

    /** ==========================================================
    * ====================== VIEW FUNCTIONS =====================
    * ======================================================== */

    /// @notice Returns the public balance of `owner`
    /// @param owner The address of the owner
    /// @return The balance of the public balance of `owner`
    #[external("public")]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> u128 {
        self.storage.public_balances.at(owner).read()
    }

    /// @notice Returns the total supply of the token
    /// @return The total supply of the token
    #[external("public")]
    #[view]
    fn total_supply() -> u128 {
        self.storage.total_supply.read()
    }

    /// @notice Returns the name of the token
    /// @return The name of the token
    #[external("public")]
    #[view]
    fn name() -> FieldCompressedString {
        self.storage.name.read()
    }

    /// @notice Returns the symbol of the token
    /// @return The symbol of the token
    #[external("public")]
    #[view]
    fn symbol() -> FieldCompressedString {
        self.storage.symbol.read()
    }

    /// @notice Returns the decimals of the token
    /// @return The decimals of the token
    #[external("public")]
    #[view]
    fn decimals() -> u8 {
        self.storage.decimals.read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    /// @notice Returns the private balance of an account
    /// @param owner The address to query
    /// @return The private balance of the address
    #[external("utility")]
    unconstrained fn balance_of_private(owner: AztecAddress) -> u128 {
        self.storage.private_balances.at(owner).balance_of()
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    /// @notice Mints tokens to a private balance
    /// @dev Mints tokens to a private balance and enqueues a public call to increase the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[external("private")]
    fn mint_to_private(to: AztecAddress, amount: u128) {
        _validate_minter(self.msg_sender(), self.storage.minter.read());

        self.internal._mint_to_private(to, amount);
    }

    /// @notice Mints tokens to an address publicly
    /// @dev Increases the public balance of `to` by `amount` and the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[external("public")]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        _validate_minter(self.msg_sender(), self.storage.minter.read());

        self.internal._mint_to_public(to, amount);
    }

    /// @notice Finalizes a mint to a commitment
    /// @dev Finalizes a mint to a commitment and updates the total supply
    /// @param commitment The partial note representing the mint commitment (privacy entrance)
    /// @param amount The amount of tokens to mint
    #[external("public")]
    fn mint_to_commitment(commitment: Field, amount: u128) {
        let sender = self.msg_sender();
        _validate_minter(sender, self.storage.minter.read());
        let completer = sender;
        self.internal._increase_total_supply(amount);
        self.internal._increase_commitment_balance(
            PartialUintNote::from_field(commitment),
            completer,
            amount,
        );

        self.emit(Transfer { from: AztecAddress::zero(), to: PRIVATE_ADDRESS_MAGIC_VALUE, amount });
    }

    /// @notice Internal function to increase the total supply by `amount`
    /// @param amount The amount to increase the total supply by
    #[external("public")]
    #[only_self]
    fn increase_total_supply_internal(amount: u128) {
        self.internal._increase_total_supply(amount);

        self.emit(Transfer { from: AztecAddress::zero(), to: PRIVATE_ADDRESS_MAGIC_VALUE, amount });
    }

    /// @notice Internal function to mint tokens to a public balance
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[external("public")]
    #[only_self]
    fn mint_to_public_internal(to: AztecAddress, amount: u128) {
        self.internal._mint_to_public(to, amount);
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns tokens from a private balance
    /// @dev Burns tokens from a private balance and enqueues a public call to update the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn burn_private(from: AztecAddress, amount: u128, _nonce: Field) {
        _validate_from_private::<3>(self.context, from);

        self.internal._burn_private(from, amount);
    }

    /// @notice Burns tokens from a public balance
    /// @dev Burns tokens from a public balance and updates the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn burn_public(from: AztecAddress, amount: u128, _nonce: Field) {
        self.internal._validate_from_public(from);

        self.internal._burn_public(from, amount);
    }

    /// @notice Decreases the total supply by `amount`
    /// @param amount The amount of tokens to decrease the total supply by
    #[external("public")]
    #[only_self]
    fn decrease_total_supply_internal(amount: u128) {
        self.internal._decrease_total_supply(amount);

        self.emit(Transfer { from: PRIVATE_ADDRESS_MAGIC_VALUE, to: AztecAddress::zero(), amount });
    }

    /// @notice Burns tokens from a public balance without validation
    /// @param from The address from which to burn the tokens
    /// @param amount The amount of tokens to burn
    #[external("public")]
    #[only_self]
    fn burn_public_internal(from: AztecAddress, amount: u128) {
        self.internal._burn_public(from, amount);
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// @notice Validates that the caller is the minter
    /// @param sender The address of the caller
    /// @param minter The address of the authorized minter
    #[contract_library_method]
    fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }

    /// @notice Decreases the private balance of `account` by `amount` and emits a private balance note with the change to account
    /// @param account The address of the account to decrease the balance of
    /// @param amount The amount of tokens to decrease the balance by
    /// @param max_notes The maximum number of notes to process in a single call
    #[internal("private")]
    fn _decrease_private_balance(account: AztecAddress, amount: u128, max_notes: u32) {
        // Subtracts `amount` from the private balance of `account`
        let change = self.internal._subtract_balance(account, amount, max_notes);
        // Increases `change` to the private balance of `account`, and emits a private balance note to account
        self.storage.private_balances.at(account).add(change).deliver(
            MessageDelivery.ONCHAIN_CONSTRAINED,
        );
    }

    /// @notice Increases the private balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[internal("private")]
    fn _increase_private_balance(to: AztecAddress, amount: u128) {
        // Increases `amount` to the private balance of `to`, and emits a private balance note to `to` from `from`
        self.storage.private_balances.at(to).add(amount).deliver(MessageDelivery.ONCHAIN_CONSTRAINED);
    }

    /// @notice Increases the public balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[internal("public")]
    fn _increase_public_balance(to: AztecAddress, amount: u128) {
        // Read the current public balance of `to`, add `amount` to it,
        let new_balance = self.storage.public_balances.at(to).read() + amount;
        // write the result back to the storage
        self.storage.public_balances.at(to).write(new_balance);
    }

    /// @notice Decreases the public balance of `from` by `amount`
    /// @param from The address of the account to decrease the balance of
    /// @param amount The amount of tokens to decrease the balance by
    #[internal("public")]
    fn _decrease_public_balance(from: AztecAddress, amount: u128) {
        // read the current public balance of `from`, subtract `amount`
        let new_balance = self.storage.public_balances.at(from).read() - amount;
        // update the public balance of `from` with the new balance
        self.storage.public_balances.at(from).write(new_balance);
    }

    /// @notice Completes a partial note
    /// @dev Completes a partial note and increases the balance of the commitment by `amount`
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param completer The address used to compute the validity commitment
    /// @param amount The amount of tokens to increase the balance of the commitment by
    #[internal("public")]
    fn _increase_commitment_balance(
        commitment: PartialUintNote,
        completer: AztecAddress,
        amount: u128,
    ) {
        commitment.complete(self.context, completer, amount);
    }

    /// @notice Subtracts balance from private balance
    /// @dev Subtracts amount from private balance and returns the change to the owner, recursively if necessary
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @param max_notes The maximum number of notes to process in a single call
    /// @return The change to return to the owner
    #[internal("private")]
    fn _subtract_balance(account: AztecAddress, amount: u128, max_notes: u32) -> u128 {
        let subtracted = self.storage.private_balances.at(account).try_sub(amount, max_notes);
        if subtracted >= amount {
            // We have achieved our goal of nullifying notes that add up to more than amount, so we return the change.
            subtracted - amount
        } else {
            // Failing to subtract any amount means that the owner was unable to produce more notes that could be nullified.
            assert(subtracted > 0, "Balance too low");

            // try_sub failed to nullify enough notes to reach the target amount, so we compute the amount remaining
            // and try again.
            let remaining = amount - subtracted;

            self.call_self.recurse_subtract_balance_internal(account, remaining)
        }
    }

    /// @notice Increases the total supply by `amount`
    /// @param amount The amount of tokens to increase the total supply by
    #[internal("public")]
    fn _increase_total_supply(amount: u128) {
        let new_supply = self.storage.total_supply.read() + amount;
        self.storage.total_supply.write(new_supply);
    }

    /// @notice Decreases the total supply by `amount`
    /// @param amount The amount to decrease the total supply by
    #[internal("public")]
    fn _decrease_total_supply(amount: u128) {
        let new_supply = self.storage.total_supply.read() - amount;
        self.storage.total_supply.write(new_supply);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @param to The address of the recipient
    /// @param completer The address used to compute the validity commitment
    /// @return The partial note that can be used to execute the transfer/mint
    #[internal("private")]
    fn _initialize_transfer_commitment(
        to: AztecAddress,
        completer: AztecAddress,
    ) -> PartialUintNote {
        let commitment = UintNote::partial(
            to,
            self.storage.private_balances.get_storage_slot(),
            self.context,
            to,
            completer,
        );

        commitment
    }

    /// @notice Mints tokens to a public balance and increases the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[internal("public")]
    fn _mint_to_public(to: AztecAddress, amount: u128) {
        self.internal._increase_public_balance(to, amount);
        self.internal._increase_total_supply(amount);

        self.emit(Transfer { from: AztecAddress::zero(), to, amount });
    }

    /// @notice Mints tokens to a private balance and enqueues a public call to increase the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[internal("private")]
    fn _mint_to_private(to: AztecAddress, amount: u128) {
        self.internal._increase_private_balance(to, amount);
        self.enqueue_self.increase_total_supply_internal(amount);
    }

    /// @notice Burns tokens from a public balance and decreases the total supply
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    #[internal("public")]
    fn _burn_public(from: AztecAddress, amount: u128) {
        self.internal._decrease_public_balance(from, amount);
        self.internal._decrease_total_supply(amount);

        self.emit(Transfer { from, to: AztecAddress::zero(), amount });
    }

    /// @notice Burns tokens from a private balance and enqueues a public call to decrease the total supply
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    #[internal("private")]
    fn _burn_private(from: AztecAddress, amount: u128) {
        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);
        self.enqueue_self.decrease_total_supply_internal(amount);
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
    #[internal("public")]
    fn _validate_from_public(from: AztecAddress) {
        if (!from.eq(self.msg_sender())) {
            assert_current_call_valid_authwit_public(self.context, from);
        }
    }

    /** ==========================================================
     * ======================= VAULT =============================
     * ======================================================== */

    // ## Note on ERC-777 assets
    // ERC-777 hooks may execute user code before a transfer (sender hook) or after it (recipient hook).
    // Users can therefore use hooks to reenter the vault, either when they send asset tokens in deposit and issue
    // functions or when they receive asset tokens in withdraw and redeem functions.
    //
    // To keep the contract safe, reentrancy should not happen at half-updated states:
    //  - Assets should be transferred into the vault BEFORE minting shares. Reentrancy would only happen before any
    //    balance is updated.
    //  - Assets should be transferred out of the vault AFTER burning shares. Reentrancy would only happen after all
    //    balances are updated.
    //
    // Note that we only worry about one hook at a time, because hooks called on the vault itself are considered safe,
    // since the vault is assume not malicious.

    /* ====================== DEPOSIT ========================= */

    /// @notice Deposits the underlying asset from a public balance and receives shares to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn deposit_public_to_public(from: AztecAddress, to: AztecAddress, assets: u128, _nonce: Field) {
        self.internal._validate_from_public(from);

        // Calculate shares to mint
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);

        // Order matters: transfer before minting to neutralize ERC-777 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));

        // Mint shares to the recipient
        self.internal._mint_to_public(to, shares);
    }

    /// @notice Deposits the underlying asset from a public balance and receives shares to a private balance
    /// @dev The shares are calculated based on the ratio (total_supply + offset) / (total_assets + 1) minus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by. Any asset excess is kept by the contract as yield.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares that should be minted to the recipient
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // Validate in public that `assets` is sufficient for the requested shares
        self.enqueue_self.settle_deposit_public_to_private_internal(from, assets, shares, _nonce);
        // Increase recipient's private balance with `shares`
        self.internal._increase_private_balance(to, shares);
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a private balance
    /// @dev The shares are calculated based on the ratio (total_supply + offset) / (total_assets + 1) minus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by. Any asset excess is kept by the contract as yield.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares that should be minted to the recipient
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // Order matters: transfer before minting to neutralize ERC-777 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_private_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));

        // Validate in public that `assets` is sufficient for the requested shares
        self.enqueue_self.settle_deposit_private_to_private_internal(assets, shares);

        // Increase recipient's private balance with `shares`
        self.internal._increase_private_balance(to, shares);
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        // Order matters: transfer before minting to neutralize ERC-777 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_private_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));

        // Calculate and mint shares to the recipient in public
        self.enqueue_self.settle_deposit_private_to_public_internal(to, assets);
    }

    /// @notice Deposits the underlying asset from a public balance and receives shares to a private balance
    /// @dev min_shares is the amount of shares that will be minted immediately in private.
    ///      Any additional shares the recipient is entitled to, will be minted through a commitment once the call is executed publicly.
    ///      This additional amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param min_shares The amount of shares that should be minted to the recipient in private
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_public_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        min_shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // Increase recipient's private balance with `min_shares`
        self.internal._increase_private_balance(to, min_shares);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to mint outstanding shares to the recipient in public
        let partial_note = self.internal._initialize_transfer_commitment(to, self.address);

        // Mint any outstanding shares without revealing the recipient and updates the shares total supply
        // Reverts if min_shares is greater than allowed
        self.enqueue_self.settle_deposit_public_to_private_exact_internal(
            from,
            partial_note.to_field(),
            assets,
            min_shares,
            _nonce,
        );
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a private balance
    /// @dev min_shares is the amount of shares that will be minted immediately in private.
    ///      Any additional shares the recipient is entitled to, will be minted through a commitment once the call is executed publicly.
    ///      This additional amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param min_shares The amount of shares that should be minted to the recipient in private
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        min_shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to mint outstanding shares to the recipient in public
        let partial_note = self.internal._initialize_transfer_commitment(to, self.address);

        // Order matters: transfer before minting to neutralize ERC-777 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_private_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));

        // Increase recipient's private balance with `min_shares`
        self.internal._increase_private_balance(to, min_shares);

        // Mint any outstanding shares without revealing the recipient and updates the shares total supply
        // Reverts if min_shares is greater than allowed
        self.enqueue_self.settle_deposit_private_to_private_exact_internal(
            partial_note.to_field(),
            assets,
            min_shares,
        );
    }

    /* ======================= ISSUE ========================== */

    /// @notice Issues exactly the requested shares to a public balance and receives the underlying asset from a public balance
    /// @dev max_assets is calculated based on the ratio (total_supply + offset) / (total_assets + 1) plus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by. Any excess assets the sender has transferred will be returned.
    ///      This excess amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn issue_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        self.internal._validate_from_public(from);

        // Calculate assets required
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_UP);

        // Order matters: transfer before minting to neutralize ERC-777 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            max_assets,
            _nonce,
        ));

        // Mint shares to the recipient
        self.internal._mint_to_public(to, shares);

        // Refund
        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            // Reimburse the sender with any excess assets sent
            // Reentrancy via the `tokens_received` hook is not an issue, as it happens after everything else is done.
            self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
                self.address,
                from,
                change,
                0,
            ));
        }
    }

    /// @notice Issues exactly the requested shares to a private balance and receives the underlying asset from a public balance
    /// @dev max_assets is calculated based on the ratio (total_supply + offset) / (total_assets + 1) plus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn issue_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // Mint shares to the recipient
        self.internal._increase_private_balance(to, shares);

        // Validate the amount of assets transferred and send back any excess
        self.enqueue_self.settle_issue_public_to_private_internal(from, shares, max_assets, _nonce);
    }

    /// @notice Issues exactly the requested shares to a public balance and receives the underlying asset from a private balance
    /// @dev Any excess assets the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn issue_private_to_public_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to refund excess assets to the sender in public
        let asset_commitment = self.call(Token::at(self.storage.asset.read())
            .initialize_transfer_commitment(from, self.address));

        // Order matters: transfer before minting to neutralize ERC-777 reentrancy via the `tokens_to_send` hook.
        // Take max_assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_private_to_public(
            from,
            self.address,
            max_assets,
            _nonce,
        ));

        // Validate max_assets in public and refund any excess to the sender with a commitment
        self.enqueue_self.settle_issue_private_to_public_exact_internal(
            asset_commitment,
            shares,
            max_assets,
            to,
        );
    }

    /// @notice Issues exactly the requested shares to a private balance and receives the underlying asset from a private balance
    /// @dev Any excess assets the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    ///      To optimize calls to this method, consider setting max_assets to an exact sum of notes, so that change is not returned twice (in private and later via commitment)
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn issue_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to refund excess assets to the sender in public
        let asset_commitment = self.call(Token::at(self.storage.asset.read())
            .initialize_transfer_commitment(from, self.address));

        // Order matters: transfer before minting to neutralize ERC-777 reentrancy via the `tokens_to_send` hook.
        // Take max_assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_private_to_public(
            from,
            self.address,
            max_assets,
            _nonce,
        ));

        // Increase recipient's private balance with `shares`
        self.internal._increase_private_balance(to, shares);

        // Validate max_assets in public and refunds any excess to the sender with a commitment
        self.enqueue_self.settle_issue_private_to_private_exact_internal(
            asset_commitment,
            shares,
            max_assets,
        );
    }

    /* ====================== WITHDRAW ======================== */

    /// @notice Withdraws an amount of the underlying asset from a public balance to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn withdraw_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        _nonce: Field,
    ) {
        self.internal._validate_from_public(from);

        // Calculate shares to burn
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_UP);

        // Order matters: transfer after burning to neutralize ERC-777 reentrancy via the `tokens_received` hook.
        // Burn the sender's shares
        self.internal._burn_public(from, shares);

        // Transfer the assets to the recipient
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Withdraws an amount of the underlying asset from a public balance to a private balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<4>(self.context, from);

        // Order matters: transfer after burning to neutralize ERC-777 reentrancy via the `tokens_received` hook.
        // Calculate and burn the sender's shares
        self.enqueue_self.settle_withdraw_public_to_private_internal(from, assets);

        // Transfer the assets to the recipient in private
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_private(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Withdraws an amount of the underlying asset from a private balance to a private balance
    /// @dev The shares are calculated with (total_supply + offset) / (total_assets + 1).
    ///      The ratio can only decrease or remain the same as time goes by. Any outstanding asset is kept by the contract as yield.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param shares The amount of shares to burn
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // Burn shares from the sender in private
        self.internal._decrease_private_balance(from, shares, INITIAL_TRANSFER_CALL_MAX_NOTES);

        // Order matters: transfer after burning to neutralize ERC-777 reentrancy via the `tokens_received` hook.
        // Validate that the shares-assets ratio is correct
        self.enqueue_self.settle_withdraw_private_to_private_internal(assets, shares);

        // Transfer the assets to the recipient in private
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_private(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Withdraws an amount of the underlying asset from a private balance to a public balance
    /// @dev max_shares is the amount of shares that will be burnt immediately in private.
    ///      Any excess shares the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    ///      To optimize calls to this method, consider setting max_shares to an exact sum of notes, so that change is not returned twice (in private and later via commitment)
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of underlying asset to withdraw
    /// @param max_shares The maximum amount of shares to burn
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_private_to_public_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        max_shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to refund excess shares to the sender in public
        let partial_note = self.internal._initialize_transfer_commitment(from, self.address);

        // Burn shares from the sender in private
        self.internal._decrease_private_balance(from, max_shares, INITIAL_TRANSFER_CALL_MAX_NOTES);

        // Burn the correct amount of shares
        // Any excess amount of shares is sent back to the sender via commitment
        // Reverts if the amount of shares required is greater than max_shares
        self.enqueue_self.settle_withdraw_private_to_public_exact_internal(
            partial_note.to_field(),
            assets,
            max_shares,
            to,
        );
    }

    /// @notice Withdraws an amount of the underlying asset from a private balance to a private balance
    /// @dev max_shares is the amount of shares that will be burnt immediately in private.
    ///      Any excess shares the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    ///      To optimize calls to this method, consider setting max_shares to an exact sum of notes, so that change is not returned twice (in private and later via commitment)
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of underlying asset to withdraw
    /// @param max_shares The maximum amount of shares to burn
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        max_shares: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to refund excess shares to the sender in public
        let partial_note = self.internal._initialize_transfer_commitment(from, self.address);

        // Burn shares from the sender in private
        self.internal._decrease_private_balance(from, max_shares, INITIAL_TRANSFER_CALL_MAX_NOTES);

        // Order matters: transfer after burning to neutralize ERC-777 reentrancy via the `tokens_received` hook.
        // Burn the correct amount of shares
        // Any excess amount of shares is sent back to the sender via commitment
        // Reverts if the amount of shares required is greater than max_shares
        self.enqueue_self.settle_withdraw_private_to_private_exact_internal(
            partial_note.to_field(),
            assets,
            max_shares,
        );

        // Transfer the assets to the recipient in private
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_private(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /* ======================= REDEEM ========================= */

    /// @notice Redeems an amount of the shares from a public balance to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    fn redeem_public_to_public(from: AztecAddress, to: AztecAddress, shares: u128, _nonce: Field) {
        self.internal._validate_from_public(from);

        // Calculate assets to redeem
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_DOWN);

        // Order matters: transfer after burning to neutralize ERC-777 reentrancy via the `tokens_received` hook.
        // Burn the sender's shares
        self.internal._burn_public(from, shares);

        // Transfer the assets to the recipient
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Redeems an amount of the shares from a private balance to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn redeem_private_to_public(from: AztecAddress, to: AztecAddress, shares: u128, _nonce: Field) {
        _validate_from_private::<4>(self.context, from);

        // Burn shares from the sender in private
        self.internal._decrease_private_balance(from, shares, INITIAL_TRANSFER_CALL_MAX_NOTES);

        // Burn shares and redeem public assets
        self.enqueue_self.settle_redeem_private_to_public_internal(to, shares);
    }

    /// @notice Redeems an amount of the shares from a private balance to a private balance
    /// @dev min_assets is the amount of assets that will be transferred to the recipient immediately in private.
    ///      Any outstanding assets the recipient is entitled to, will be sent through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to burn
    /// @param min_assets The minimum amount of assets to withdraw, immediately in private
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn redeem_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        min_assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to transfer outstanding assets to the recipient in public
        let asset_commitment = self.call(Token::at(self.storage.asset.read())
            .initialize_transfer_commitment(to, self.address));

        // Burn shares from the sender in private
        self.internal._decrease_private_balance(from, shares, INITIAL_TRANSFER_CALL_MAX_NOTES);

        // Order matters: transfer after burning to neutralize ERC-777 reentrancy via the `tokens_received` hook.
        // Transfers any outstanding assets without revealing the recipient
        // Reverts if min_assets is greater than allowed
        self.enqueue_self.settle_redeem_private_to_private_exact_internal(
            asset_commitment,
            shares,
            min_assets,
        );

        // Transfer min_assets to the recipient
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_private(
            self.address,
            to,
            min_assets,
            0,
        ));
    }

    /// @notice Redeems an amount of the shares from a public balance to a private balance
    /// @dev min_assets is the amount of assets that will be transferred to the recipient immediately in private.
    ///      Any outstanding assets the recipient is entitled to, will be sent through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param min_assets The minimum amount of assets to withdraw, immediately in private
    /// @param _nonce The nonce used for authwitness
    #[external("private")]
    fn redeem_public_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        min_assets: u128,
        _nonce: Field,
    ) {
        _validate_from_private::<5>(self.context, from);

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to transfer outstanding assets to the recipient in public
        let asset_commitment = self.call(Token::at(self.storage.asset.read())
            .initialize_transfer_commitment(to, self.address));

        // Order matters: transfer after burning to neutralize ERC-777 reentrancy via the `tokens_received` hook.
        // Transfers any outstanding assets without revealing the recipient
        // Reverts if min_assets is greater than allowed
        self.enqueue_self.settle_redeem_public_to_private_exact_internal(
            from,
            asset_commitment,
            shares,
            min_assets,
        );

        // Transfer min_assets to the recipient
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_private(
            self.address,
            to,
            min_assets,
            0,
        ));
    }

    /** ==========================================================
     * ====================== VAULT VIEW =========================
     * ======================================================== */

    /// @notice Returns the underlying asset address
    /// @return The address of the underlying asset
    #[external("public")]
    #[view]
    fn asset() -> AztecAddress {
        self.storage.asset.read()
    }

    /// @notice Returns the total amount of underlying assets held by the vault
    /// @return The total amount of assets held by the vault
    #[external("public")]
    #[view]
    fn total_assets() -> u128 {
        self.internal._total_assets()
    }

    /// @notice Converts an amount of assets to shares using the current exchange rate
    /// @param assets The amount of assets to convert
    /// @return The equivalent amount of shares
    #[external("public")]
    #[view]
    fn convert_to_shares(assets: u128) -> u128 {
        self.internal._convert_to_shares(assets, self.internal._total_assets(), ROUND_DOWN)
    }

    /// @notice Converts an amount of shares to assets using the current exchange rate
    /// @param shares The amount of shares to convert
    /// @return The equivalent amount of assets
    #[external("public")]
    #[view]
    fn convert_to_assets(shares: u128) -> u128 {
        self.internal._convert_to_assets(shares, self.internal._total_assets(), ROUND_DOWN)
    }

    /// @dev Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver, through a deposit call.
    /// @param receiver The address of the receiver
    /// @return The maximum amount of assets that can be deposited
    #[external("public")]
    #[view]
    fn max_deposit(receiver: AztecAddress) -> u128 {
        self.internal._max_deposit(receiver)
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given current on-chain conditions.
    /// @param assets The amount of assets to deposit
    /// @return The amount of shares that would be minted
    #[external("public")]
    #[view]
    fn preview_deposit(assets: u128) -> u128 {
        self.internal._preview_deposit(assets)
    }

    /// @dev Returns the maximum amount of the Vault shares that can be issued for the receiver, through a mint call.
    /// @param receiver The address of the receiver
    /// @return The maximum amount of shares that can be issued
    #[external("public")]
    #[view]
    fn max_issue(receiver: AztecAddress) -> u128 {
        self.internal._max_issue(receiver)
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their issue at the current block, given current on-chain conditions.
    /// @param shares The amount of shares to issue
    /// @return The amount of assets required to issue the shares
    #[external("public")]
    #[view]
    fn preview_issue(shares: u128) -> u128 {
        self.internal._preview_issue(shares)
    }

    /// @dev Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the Vault, through a withdraw call.
    /// @notice This does NOT include private balance - private holders must track their own balance.
    /// @param owner The address of the owner
    /// @return The maximum amount of assets that can be withdrawn
    #[external("public")]
    #[view]
    fn max_withdraw(owner: AztecAddress) -> u128 {
        self.internal._max_withdraw(owner)
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their withdraw at the current block, given current on-chain conditions.
    /// @param assets The amount of assets to withdraw
    /// @return The amount of shares that would be withdrawn
    #[external("public")]
    #[view]
    fn preview_withdraw(assets: u128) -> u128 {
        self.internal._preview_withdraw(assets)
    }

    /// @dev Returns the maximum amount of the Vault shares that can be redeemed from the owner balance in the Vault, through a redeem call.
    /// @notice This does NOT include private balance - private holders must track their own balance.
    /// @param owner The address of the owner
    /// @return The maximum amount of shares that can be redeemed
    #[external("public")]
    #[view]
    fn max_redeem(owner: AztecAddress) -> u128 {
        self.internal._max_redeem(owner)
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their redeem at the current block, given current on-chain conditions.
    /// @param shares The amount of shares to redeem
    /// @return The amount of assets that would be redeemed
    #[external("public")]
    #[view]
    fn preview_redeem(shares: u128) -> u128 {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_DOWN);
        assets
    }

    /** ==========================================================
     * ==================== VAULT INTERNALS ======================
     * ======================================================== */

    /// @notice Burns shares held in public for a given amount of assets
    /// @param from The address of the sender
    /// @param assets The amount of assets to burn shares for
    #[external("public")]
    #[only_self]
    fn settle_withdraw_public_to_private_internal(from: AztecAddress, assets: u128) {
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_UP);

        self.internal._burn_public(from, shares);
    }

    /// @notice Validates that the requested shares amount is valid for the given assets
    /// @param assets The amount of assets being withdrawn
    /// @param shares The amount of shares being burned
    #[external("public")]
    #[only_self]
    fn settle_withdraw_private_to_private_internal(assets: u128, shares: u128) {
        let total_assets = self.internal._total_assets();
        let min_shares = self.internal._convert_to_shares(assets, total_assets, ROUND_UP);

        assert(min_shares <= shares, "Insufficient shares burnt");

        self.internal._decrease_total_supply(shares);

        self.emit(
            Transfer {
                from: PRIVATE_ADDRESS_MAGIC_VALUE,
                to: AztecAddress::zero(),
                amount: shares,
            },
        );
    }

    /// @notice Withdraws assets to a public balance for a given amount of shares
    /// @param to The address of the recipient
    /// @param shares The amount of shares being redeemed
    #[external("public")]
    #[only_self]
    fn settle_redeem_private_to_public_internal(to: AztecAddress, shares: u128) {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_DOWN);

        // Order matters: transfer after burning to neutralize ERC-777 reentrancy via the `tokens_received` hook.
        // Finalize burning shares by decreasing total supply
        self.internal._decrease_total_supply(shares);

        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));

        self.emit(
            Transfer {
                from: PRIVATE_ADDRESS_MAGIC_VALUE,
                to: AztecAddress::zero(),
                amount: shares,
            },
        );
    }

    /// @notice Mints shares to a public balance for a given amount of assets
    /// @param to The address of the recipient
    /// @param assets The amount of assets being deposited
    #[external("public")]
    #[only_self]
    fn settle_deposit_private_to_public_internal(to: AztecAddress, assets: u128) {
        let total_assets = self.internal._total_assets() - assets;
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);

        self.internal._mint_to_public(to, shares);
    }

    /// @notice Validates that the requested shares amount is valid for the deposited assets
    /// @param from The address of the sender
    /// @param assets The amount of assets being deposited
    /// @param shares The amount of shares being issued
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    #[only_self]
    fn settle_deposit_public_to_private_internal(
        from: AztecAddress,
        assets: u128,
        shares: u128,
        _nonce: Field,
    ) {
        let total_assets = self.internal._total_assets();
        let max_shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);

        assert(shares <= max_shares, "Too many shares requested");

        // Order matters: transfer before minting to neutralize ERC-777 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));

        // Finalize minting shares by increasing total supply
        self.internal._increase_total_supply(shares);

        self.emit(
            Transfer {
                from: AztecAddress::zero(),
                to: PRIVATE_ADDRESS_MAGIC_VALUE,
                amount: shares,
            },
        );
    }

    /// @notice Validates that the requested shares amount is valid for the deposited assets
    /// @param assets The amount of assets being deposited
    /// @param shares The amount of shares being issued
    #[external("public")]
    #[only_self]
    fn settle_deposit_private_to_private_internal(assets: u128, shares: u128) {
        let total_assets = self.internal._total_assets() - assets;
        let max_shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);

        assert(shares <= max_shares, "Too many shares requested");

        // Finalize minting shares by increasing total supply
        self.internal._increase_total_supply(shares);

        self.emit(
            Transfer {
                from: AztecAddress::zero(),
                to: PRIVATE_ADDRESS_MAGIC_VALUE,
                amount: shares,
            },
        );
    }

    /// @notice Decreases shares total supply and refunds excess shares via commitment
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of assets being withdrawn
    /// @param max_shares The maximum amount of shares that should be redeemed
    /// @param to The address of the recipient
    #[external("public")]
    #[only_self]
    fn settle_withdraw_private_to_public_exact_internal(
        commitment: Field,
        assets: u128,
        max_shares: u128,
        to: AztecAddress,
    ) {
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_UP);

        let surplus = max_shares - shares; // Reverts with underflow if invalid
        if surplus > 0 {
            self.internal._increase_commitment_balance(
                PartialUintNote::from_field(commitment),
                self.address,
                surplus,
            );
        }

        // Order matters: transfer after burning to neutralize ERC-777 reentrancy via the `tokens_received` hook.
        // Finalize burning shares by decreasing total supply
        self.internal._decrease_total_supply(shares);

        // Transfer the assets to the sender
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));

        self.emit(
            Transfer {
                from: PRIVATE_ADDRESS_MAGIC_VALUE,
                to: AztecAddress::zero(),
                amount: shares,
            },
        );
    }

    /// @notice Decreases shares total supply and refunds excess shares via commitment
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of assets being withdrawn
    /// @param max_shares The maximum amount of shares that should be redeemed
    #[external("public")]
    #[only_self]
    fn settle_withdraw_private_to_private_exact_internal(
        commitment: Field,
        assets: u128,
        max_shares: u128,
    ) {
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_UP);

        let surplus = max_shares - shares; // Reverts with underflow if invalid
        if surplus > 0 {
            self.internal._increase_commitment_balance(
                PartialUintNote::from_field(commitment),
                self.address,
                surplus,
            );
        }

        // Finalize burning shares by decreasing total supply
        self.internal._decrease_total_supply(shares);

        self.emit(
            Transfer {
                from: PRIVATE_ADDRESS_MAGIC_VALUE,
                to: AztecAddress::zero(),
                amount: shares,
            },
        );
    }

    /// @notice Increases shares total supply and issues outstanding shares via commitment
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of assets being deposited
    /// @param min_shares The minimum amount of shares that should be issued
    #[external("public")]
    #[only_self]
    fn settle_deposit_private_to_private_exact_internal(
        commitment: Field,
        assets: u128,
        min_shares: u128,
    ) {
        let total_assets = self.internal._total_assets() - assets;
        let max_shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);

        let outstanding_shares = max_shares - min_shares; // Reverts with underflow if invalid
        if outstanding_shares > 0 {
            self.internal._increase_commitment_balance(
                PartialUintNote::from_field(commitment),
                self.address,
                outstanding_shares,
            );
        }

        self.internal._increase_total_supply(max_shares);

        self.emit(
            Transfer {
                from: AztecAddress::zero(),
                to: PRIVATE_ADDRESS_MAGIC_VALUE,
                amount: max_shares,
            },
        );
    }

    /// @notice Increases shares total supply and issues outstanding shares via commitment
    /// @param from The address of the sender
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of assets being deposited
    /// @param min_shares The minimum amount of shares that should be issued
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    #[only_self]
    fn settle_deposit_public_to_private_exact_internal(
        from: AztecAddress,
        commitment: Field,
        assets: u128,
        min_shares: u128,
        _nonce: Field,
    ) {
        let total_assets = self.internal._total_assets();
        let max_shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);
        let outstanding_shares = max_shares - min_shares; // Reverts with underflow if invalid

        // Order matters: transfer before minting to neutralize ERC-777 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));

        if outstanding_shares > 0 {
            self.internal._increase_commitment_balance(
                PartialUintNote::from_field(commitment),
                self.address,
                outstanding_shares,
            );
        }

        self.internal._increase_total_supply(max_shares);

        self.emit(
            Transfer {
                from: AztecAddress::zero(),
                to: PRIVATE_ADDRESS_MAGIC_VALUE,
                amount: max_shares,
            },
        );
    }

    /// @notice Refunds excess assets to the sender via commitment while validating the shares amount requested
    /// @param asset_commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of shares being issued
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param to The address of the recipient
    #[external("public")]
    #[only_self]
    fn settle_issue_private_to_public_exact_internal(
        asset_commitment: Field,
        shares: u128,
        max_assets: u128,
        to: AztecAddress,
    ) {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets - max_assets, ROUND_UP);

        self.internal._mint_to_public(to, shares);

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            self.call(Token::at(self.storage.asset.read()).transfer_public_to_commitment(
                self.address,
                asset_commitment,
                change,
                0,
            ));
        }
    }

    /// @notice Refunds excess assets to the sender via commitment while validating the shares amount requested
    /// @param asset_commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of shares being issued
    /// @param max_assets The maximum amount of assets that should be deposited
    #[external("public")]
    #[only_self]
    fn settle_issue_private_to_private_exact_internal(
        asset_commitment: Field,
        shares: u128,
        max_assets: u128,
    ) {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets - max_assets, ROUND_UP);

        self.internal._increase_total_supply(shares);

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            self.call(Token::at(self.storage.asset.read()).transfer_public_to_commitment(
                self.address,
                asset_commitment,
                change,
                0,
            ));
        }

        self.emit(
            Transfer {
                from: AztecAddress::zero(),
                to: PRIVATE_ADDRESS_MAGIC_VALUE,
                amount: shares,
            },
        );
    }

    /// @notice Validates share redemption rate and withdraws any outstanding assets via commitment
    /// @param asset_commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of shares being redeemed
    /// @param min_assets The minimum amount of assets that should be withdrawn
    #[external("public")]
    #[only_self]
    fn settle_redeem_private_to_private_exact_internal(
        asset_commitment: Field,
        shares: u128,
        min_assets: u128,
    ) {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_DOWN);

        // Finalize burning shares by decreasing total supply
        self.internal._decrease_total_supply(shares);

        let outstanding_assets = assets - min_assets; // Reverts with underflow if invalid
        if outstanding_assets > 0 {
            self.call(Token::at(self.storage.asset.read()).transfer_public_to_commitment(
                self.address,
                asset_commitment,
                outstanding_assets,
                0,
            ));
        }

        self.emit(
            Transfer {
                from: PRIVATE_ADDRESS_MAGIC_VALUE,
                to: AztecAddress::zero(),
                amount: shares,
            },
        );
    }

    /// @notice Validates share redemption rate and withdraws any outstanding assets via commitment
    /// @param from The address of the sender
    /// @param asset_commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of shares being redeemed
    /// @param min_assets The minimum amount of assets that should be withdrawn
    #[external("public")]
    #[only_self]
    fn settle_redeem_public_to_private_exact_internal(
        from: AztecAddress,
        asset_commitment: Field,
        shares: u128,
        min_assets: u128,
    ) {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_DOWN);

        // Burn the sender's shares
        self.internal._burn_public(from, shares);

        let outstanding_assets = assets - min_assets; // Reverts with underflow if invalid
        if outstanding_assets > 0 {
            self.call(Token::at(self.storage.asset.read()).transfer_public_to_commitment(
                self.address,
                asset_commitment,
                outstanding_assets,
                0,
            ));
        }
    }

    /// @notice Validates issuance rate and refunds excess assets being deposited from a public balance
    /// @param from The address of the sender
    /// @param shares The amount of shares being issued
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param _nonce The nonce used for authwitness
    #[external("public")]
    #[only_self]
    fn settle_issue_public_to_private_internal(
        from: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_UP);

        // Order matters: transfer before minting to neutralize ERC-777 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            max_assets,
            _nonce,
        ));

        // Increase total_supply
        self.internal._increase_total_supply(shares);

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
                self.address,
                from,
                change,
                0,
            ));
        }

        self.emit(
            Transfer {
                from: AztecAddress::zero(),
                to: PRIVATE_ADDRESS_MAGIC_VALUE,
                amount: shares,
            },
        );
    }

    /** ==========================================================
     * ================== VAULT LIBRARIES ========================
     * ======================================================== */

    /// @notice Returns the total amount of underlying assets held by the vault
    /// @return The total amount of assets held by the vault
    #[internal("public")]
    fn _total_assets() -> u128 {
        let total_assets =
            self.view(Token::at(self.storage.asset.read()).balance_of_public(self.address));
        total_assets
    }

    /// @notice Converts an amount of assets to shares using the current exchange rate
    /// @param assets The amount of assets to convert
    /// @param total_assets The total amount of assets in the vault
    /// @param rounding The rounding direction (ROUND_UP or ROUND_DOWN)
    /// @return The equivalent amount of shares
    #[internal("public")]
    fn _convert_to_shares(assets: u128, total_assets: u128, rounding: bool) -> u128 {
        // TODO: handle overflow
        // TODO: optimize rounding
        let mul_term =
            assets * (self.storage.total_supply.read() + self.storage.vault_offset.read());
        let denominator = (total_assets + 1);
        let mut shares = mul_term / denominator;
        if (rounding == ROUND_UP) & (mul_term % denominator > 0) {
            shares = shares + 1;
        }
        shares
    }

    /// @notice Converts an amount of shares to assets using the current exchange rate
    /// @param shares The amount of shares to convert
    /// @param total_assets The total amount of assets in the vault
    /// @param rounding The rounding direction (ROUND_UP or ROUND_DOWN)
    /// @return The equivalent amount of assets
    #[internal("public")]
    fn _convert_to_assets(shares: u128, total_assets: u128, rounding: bool) -> u128 {
        // TODO: handle overflow
        // TODO: optimize rounding
        let mul_term = shares * (total_assets + 1);
        let denominator = (self.storage.total_supply.read() + self.storage.vault_offset.read());
        let mut assets = mul_term / denominator;
        if (rounding == ROUND_UP) & (mul_term % denominator > 0) {
            assets = assets + 1;
        }
        assets
    }

    /// @notice Offset that determines the rate of virtual shares to virtual assets in the vault, which itself determines the initial exchange rate.
    /// While not fully preventing inflation attacks, analysis shows that offset=1 makes it non-profitable even if an attacker is able to capture value from multiple user deposits,
    /// as a result of the value being captured by the virtual shares (out of the attacker's donation) matching the attacker's expected gains.
    /// With a larger offset, the attack becomes orders of magnitude more expensive than it is profitable.
    /// @return The offset value
    #[external("public")]
    #[view]
    fn get_vault_offset() -> u128 {
        self.storage.vault_offset.read()
    }

    /// @dev Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver, through a deposit call.
    /// @dev The receiver parameter is accepted for ERC-4626 compatibility and future extensibility, but is not used by the default implementation.
    /// @param _receiver The address of the receiver
    /// @return The maximum amount of assets that can be deposited
    #[internal("public")]
    fn _max_deposit(_receiver: AztecAddress) -> u128 {
        MAX_U128_VALUE
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given current on-chain conditions.
    /// @param assets The amount of assets to deposit
    /// @return The amount of shares that would be minted
    #[internal("public")]
    fn _preview_deposit(assets: u128) -> u128 {
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);
        shares
    }

    /// @dev Returns the maximum amount of the Vault shares that can be issued for the receiver, through a mint call.
    /// @dev The receiver parameter is accepted for ERC-4626 compatibility and future extensibility, but is not used by the default implementation.
    /// @param _receiver The address of the receiver
    /// @return The maximum amount of shares that can be issued
    #[internal("public")]
    fn _max_issue(_receiver: AztecAddress) -> u128 {
        MAX_U128_VALUE
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their issue at the current block, given current on-chain conditions.
    /// @param shares The amount of shares to deposit
    /// @return The amount of assets that would be issued
    #[internal("public")]
    fn _preview_issue(shares: u128) -> u128 {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_UP);
        assets
    }

    /// @dev Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the Vault, through a withdraw call.
    /// @notice This does NOT include private balance - private holders must track their own balance.
    /// @param owner The address of the owner
    /// @return The maximum amount of assets that can be withdrawn
    #[internal("public")]
    fn _max_withdraw(owner: AztecAddress) -> u128 {
        self.internal._preview_redeem(self.internal._max_redeem(owner))
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their withdraw at the current block, given current on-chain conditions.
    /// @param assets The amount of assets to withdraw
    /// @return The amount of shares that would be redeemed
    #[internal("public")]
    fn _preview_withdraw(assets: u128) -> u128 {
        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_UP);
        shares
    }

    /// @dev Returns the maximum amount of the Vault shares that can be redeemed from the owner balance in the Vault, through a redeem call.
    /// @notice This does NOT include private balance - private holders must track their own balance.
    /// @param owner The address of the owner
    /// @return The maximum amount of shares that can be redeemed
    #[internal("public")]
    fn _max_redeem(owner: AztecAddress) -> u128 {
        self.storage.public_balances.at(owner).read()
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their redeem at the current block, given current on-chain conditions.
    /// @param shares The amount of shares to redeem
    /// @return The amount of assets that would be redeemed
    #[internal("public")]
    fn _preview_redeem(shares: u128) -> u128 {
        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_DOWN);
        assets
    }
}
