pub mod types;
mod test;

use aztec::macros::aztec;

#[aztec]
pub contract Token {
    // aztec library
    use aztec::{
        authwit::auth::{
            assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
        },
        context::{PrivateContext, PublicContext},
        macros::{
            functions::{initializer, internal, private, public, utility, view},
            storage::storage,
        },
        messages::logs::note::encode_and_encrypt_note,
        protocol_types::{
            address::AztecAddress,
            constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            contract_class_id::ContractClassId,
            traits::{FromField, ToField},
        },
        state_vars::{Map, public_immutable::PublicImmutable, public_mutable::PublicMutable},
    };
    // note library
    use uint_note::uint_note::{PartialUintNote, UintNote};
    // compression library
    use compressed_string::FieldCompressedString;
    // contract instance registry
    use contract_instance_registry::ContractInstanceRegistry;
    // private balance library
    use crate::types::balance_set::BalanceSet;

    // gas-optimized max notes for initial transfer call
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    // max notes transfer for recursive transfer call if initial max notes are exceeded
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    // Rounding direction that the vault uses to calculate shares and assets
    global ROUND_DOWN: bool = false;
    global ROUND_UP: bool = true;

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
        asset: PublicImmutable<AztecAddress, Context>,
    }

    /// @notice Initializes the token with an asset
    /// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param asset The underlying asset for the yield bearing token
    #[public]
    #[initializer]
    fn constructor_with_asset(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        asset: AztecAddress,
        upgrade_authority: AztecAddress,
    ) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.decimals.initialize(decimals);
        storage.asset.initialize(asset);

        storage.upgrade_authority.initialize(upgrade_authority);
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

        // Inline _mint_to_public
        let to_balance_storage = storage.public_balances.at(to);
        let to_new_balance = to_balance_storage.read() + initial_supply;
        to_balance_storage.write(to_new_balance);

        let total_supply_storage = storage.total_supply;
        let new_supply = total_supply_storage.read() + initial_supply;
        total_supply_storage.write(new_supply);

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
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<4>(&mut context, from);
        }

        // Inline _decrease_private_balance and _subtract_balance logic
        let this_address = context.this_address();
        let private_balances_at_from = storage.private_balances.at(from);
        let subtracted = private_balances_at_from.try_sub(amount, INITIAL_TRANSFER_CALL_MAX_NOTES);
        assert(subtracted > 0, "Balance too low");

        let change = if subtracted >= amount {
            subtracted - amount
        } else {
            let remaining = amount - subtracted;
            Token::at(this_address).recurse_subtract_balance_internal(from, remaining).call(&mut context)
        };

        // Inline _increase_private_balance for change
        if change > 0 {
            private_balances_at_from.add(from, change).emit(encode_and_encrypt_note(&mut context, from));
        }

        // Direct enqueue instead of internal function call
        Token::at(this_address).increase_public_balance_internal(to, amount).enqueue(&mut context);
    }

    /// @notice Transfer tokens from private balance to public balance and initializes a commitment
    /// @dev Spends notes, emits a new note (UintNote) with any remaining change, enqueues a public call, and returns a partial note.
    ///      The sender will be used as the completer for the initialized partial note.
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
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<4>(&mut context, from);
        }

        // Inline _decrease_private_balance and _subtract_balance logic
        let this_address = context.this_address();
        let private_balances_at_from = storage.private_balances.at(from);
        let subtracted = private_balances_at_from.try_sub(amount, INITIAL_TRANSFER_CALL_MAX_NOTES);
        assert(subtracted > 0, "Balance too low");

        let change = if subtracted >= amount {
            subtracted - amount
        } else {
            let remaining = amount - subtracted;
            Token::at(this_address).recurse_subtract_balance_internal(from, remaining).call(&mut context)
        };

        // Inline _increase_private_balance for change
        if change > 0 {
            private_balances_at_from.add(from, change).emit(encode_and_encrypt_note(&mut context, from));
        }

        Token::at(this_address).increase_public_balance_internal(to, amount).enqueue(&mut context);

        // Inline _initialize_transfer_commitment
        let sender = context.msg_sender();
        let private_balances_at_to = storage.private_balances.at(to);
        let commitment = UintNote::partial(
            to,
            private_balances_at_to.set.storage_slot,
            &mut context,
            to,
            sender,
        );
        commitment.to_field()
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
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<4>(&mut context, from);
        }

        // Inline _decrease_private_balance and _subtract_balance logic
        let this_address = context.this_address();
        let private_balances_at_from = storage.private_balances.at(from);
        let subtracted = private_balances_at_from.try_sub(amount, INITIAL_TRANSFER_CALL_MAX_NOTES);
        assert(subtracted > 0, "Balance too low");

        let change = if subtracted >= amount {
            subtracted - amount
        } else {
            let remaining = amount - subtracted;
            Token::at(this_address).recurse_subtract_balance_internal(from, remaining).call(&mut context)
        };

        // Inline _increase_private_balance for change
        if change > 0 {
            private_balances_at_from.add(from, change).emit(encode_and_encrypt_note(&mut context, from));
        }

        // Inline _increase_private_balance for recipient
        storage.private_balances.at(to).add(to, amount).emit(encode_and_encrypt_note(&mut context, to));
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
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<4>(&mut context, from);
        }

        // Inline _decrease_private_balance and _subtract_balance logic
        let this_address = context.this_address();
        let private_balances_at_from = storage.private_balances.at(from);
        let subtracted = private_balances_at_from.try_sub(amount, INITIAL_TRANSFER_CALL_MAX_NOTES);
        assert(subtracted > 0, "Balance too low");

        let change = if subtracted >= amount {
            subtracted - amount
        } else {
            let remaining = amount - subtracted;
            Token::at(this_address).recurse_subtract_balance_internal(from, remaining).call(&mut context)
        };

        // Inline _increase_private_balance for change
        if change > 0 {
            private_balances_at_from.add(from, change).emit(encode_and_encrypt_note(&mut context, from));
        }

        let completer = context.msg_sender();
        PartialUintNote::from_field(commitment).complete_from_private(&mut context, completer, amount);
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
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<4>(&mut context, from);
        }

        Token::at(context.this_address()).decrease_public_balance_internal(from, amount).enqueue(&mut context);

        // Inline _increase_private_balance
        storage.private_balances.at(to).add(to, amount).emit(encode_and_encrypt_note(&mut context, to));
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    /// @dev Returns a partial note that can be used to execute transfers/mints
    /// @param to The address of the recipient
    /// @param completer The address allowed to complete the partial note
    /// @return commitment The partial note initialized for the transfer/mint commitment
    #[private]
    fn initialize_transfer_commitment(to: AztecAddress, completer: AztecAddress) -> Field {
        // Inline _initialize_transfer_commitment
        let private_balances_at_to = storage.private_balances.at(to);
        let commitment = UintNote::partial(
            to,
            private_balances_at_to.set.storage_slot,
            &mut context,
            to,
            completer,
        );
        commitment.to_field()
    }

    /// @notice Recursively subtracts balance from commitment
    /// @dev Used to subtract balances that exceed the max notes limit
    /// @param account The address of the account to subtract the balance from
    /// @param amount The amount of tokens to subtract
    /// @return The change to return to the owner
    #[private]
    #[internal]
    fn recurse_subtract_balance_internal(account: AztecAddress, amount: u128) -> u128 {
        // Inline _subtract_balance
        let private_balances_at_account = storage.private_balances.at(account);
        let subtracted = private_balances_at_account.try_sub(amount, RECURSIVE_TRANSFER_CALL_MAX_NOTES);
        assert(subtracted > 0, "Balance too low");
        if subtracted >= amount {
            subtracted - amount
        } else {
            let remaining = amount - subtracted;
            let this_address = context.this_address();
            Token::at(this_address).recurse_subtract_balance_internal(account, remaining).call(&mut context)
        }
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
        // Inline _validate_from_public
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, from);
        }

        // Inline _decrease_public_balance
        let from_balance_storage = storage.public_balances.at(from);
        let from_new_balance = from_balance_storage.read() - amount;
        from_balance_storage.write(from_new_balance);

        // Inline _increase_public_balance
        let to_balance_storage = storage.public_balances.at(to);
        let to_new_balance = to_balance_storage.read() + amount;
        to_balance_storage.write(to_new_balance);
    }

    /// @notice Finalizes a transfer of token `amount` from public balance of `from` to a commitment of `to`
    /// @dev The transfer must be prepared by calling `initialize_transfer_commitment` first and the resulting
    /// `commitment` must be passed as an argument to this function.
    /// @dev The sender will be used as the completer for the partial note.
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
        // Inline _validate_from_public
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, from);
        }

        // Inline _decrease_public_balance
        let from_balance_storage = storage.public_balances.at(from);
        let from_new_balance = from_balance_storage.read() - amount;
        from_balance_storage.write(from_new_balance);

        // Inline _increase_commitment_balance
        let completer = context.msg_sender();
        PartialUintNote::from_field(commitment).complete(&mut context, completer, amount);
    }

    /// @notice Increases the public balance of `to` by `amount`
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to increase the balance by
    #[public]
    #[internal]
    fn increase_public_balance_internal(to: AztecAddress, amount: u128) {
        // Inline _increase_public_balance
        let to_balance_storage = storage.public_balances.at(to);
        let to_new_balance = to_balance_storage.read() + amount;
        to_balance_storage.write(to_new_balance);
    }

    /// @notice Decreases the public balance of `from` by `amount`
    /// @param from The address of the sender
    /// @param amount The amount of tokens to decrease the balance by
    #[public]
    #[internal]
    fn decrease_public_balance_internal(from: AztecAddress, amount: u128) {
        // Inline _decrease_public_balance
        let from_balance_storage = storage.public_balances.at(from);
        let from_new_balance = from_balance_storage.read() - amount;
        from_balance_storage.write(from_new_balance);
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
    unconstrained fn balance_of_private(owner: AztecAddress) -> u128 {
        storage.private_balances.at(owner).balance_of()
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    /// @notice Mints tokens to a commitment
    /// @dev Mints tokens to a commitment and enqueues a public call to increase the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[private]
    fn mint_to_private(to: AztecAddress, amount: u128) {
        // Inline _validate_minter
        let minter = storage.minter.read();
        let sender = context.msg_sender();
        assert(minter.eq(sender), "caller is not minter");

        // Inline _mint_to_private and _increase_private_balance
        storage.private_balances.at(to).add(to, amount).emit(encode_and_encrypt_note(&mut context, to));

        Token::at(context.this_address()).increase_total_supply_internal(amount).enqueue(&mut context);
    }

    /// @notice Mints tokens to a public balance
    /// @dev Increases the public balance of `to` by `amount` and the total supply
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to mint
    #[public]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        // Inline _validate_minter
        let minter = storage.minter.read();
        let sender = context.msg_sender();
        assert(minter.eq(sender), "caller is not minter");

        // Inline _mint_to_public, _increase_public_balance and _increase_total_supply
        let to_balance_storage = storage.public_balances.at(to);
        let to_new_balance = to_balance_storage.read() + amount;
        to_balance_storage.write(to_new_balance);

        let total_supply_storage = storage.total_supply;
        let new_supply = total_supply_storage.read() + amount;
        total_supply_storage.write(new_supply);
    }

    /// @notice Finalizes a mint to a commitment
    /// @dev Finalizes a mint to a commitment and updates the total supply
    /// @param commitment The partial note representing the mint commitment (privacy entrance)
    /// @param amount The amount of tokens to mint
    #[public]
    fn mint_to_commitment(commitment: Field, amount: u128) {
        let sender = context.msg_sender();
        // Inline _validate_minter
        let minter = storage.minter.read();
        assert(minter.eq(sender), "caller is not minter");

        // Inline _increase_total_supply
        let total_supply_storage = storage.total_supply;
        let new_supply = total_supply_storage.read() + amount;
        total_supply_storage.write(new_supply);

        // Inline _increase_commitment_balance
        PartialUintNote::from_field(commitment).complete(&mut context, sender, amount);
    }

    #[public]
    #[internal]
    fn increase_total_supply_internal(amount: u128) {
        // Inline _increase_total_supply
        let total_supply_storage = storage.total_supply;
        let new_supply = total_supply_storage.read() + amount;
        total_supply_storage.write(new_supply);
    }

    #[public]
    #[internal]
    fn mint_to_public_internal(to: AztecAddress, amount: u128) {
        // Inline _mint_to_public, _increase_public_balance and _increase_total_supply
        let to_balance_storage = storage.public_balances.at(to);
        let to_new_balance = to_balance_storage.read() + amount;
        to_balance_storage.write(to_new_balance);

        let total_supply_storage = storage.total_supply;
        let new_supply = total_supply_storage.read() + amount;
        total_supply_storage.write(new_supply);
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
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<3>(&mut context, from);
        }

        // Inline _burn_private and _decrease_private_balance
        let this_address = context.this_address();
        let private_balances_at_from = storage.private_balances.at(from);
        let subtracted = private_balances_at_from.try_sub(amount, INITIAL_TRANSFER_CALL_MAX_NOTES);
        assert(subtracted > 0, "Balance too low");

        let change = if subtracted >= amount {
            subtracted - amount
        } else {
            let remaining = amount - subtracted;
            Token::at(this_address).recurse_subtract_balance_internal(from, remaining).call(&mut context)
        };

        // Add change back
        if change > 0 {
            private_balances_at_from.add(from, change).emit(encode_and_encrypt_note(&mut context, from));
        }

        Token::at(this_address).decrease_total_supply_internal(amount).enqueue(&mut context);
    }

    /// @notice Burns tokens from a public balance
    /// @dev Burns tokens from a public balance and updates the total supply
    /// @param from The address of the sender
    /// @param amount The amount of tokens to burn
    /// @param _nonce The nonce used for authwitness
    #[public]
    fn burn_public(from: AztecAddress, amount: u128, _nonce: Field) {
        // Inline _validate_from_public
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, from);
        }

        // Inline _burn_public, _decrease_public_balance and _decrease_total_supply
        let from_balance_storage = storage.public_balances.at(from);
        let from_new_balance = from_balance_storage.read() - amount;
        from_balance_storage.write(from_new_balance);

        let total_supply_storage = storage.total_supply;
        let new_supply = total_supply_storage.read() - amount;
        total_supply_storage.write(new_supply);
    }

    /// @notice Decreases the total supply by `amount`
    /// @param amount The amount of tokens to decrease the total supply by
    #[public]
    #[internal]
    fn decrease_total_supply_internal(amount: u128) {
        // Inline _decrease_total_supply
        let total_supply_storage = storage.total_supply;
        let new_supply = total_supply_storage.read() - amount;
        total_supply_storage.write(new_supply);
    }

    /// @notice Burns tokens from a public balance without validation
    /// @param from The address from which to burn the tokens
    /// @param amount The amount of tokens to burn
    #[public]
    #[internal]
    fn burn_public_internal(from: AztecAddress, amount: u128) {
        // Inline _burn_public, _decrease_public_balance and _decrease_total_supply
        let from_balance_storage = storage.public_balances.at(from);
        let from_new_balance = from_balance_storage.read() - amount;
        from_balance_storage.write(from_new_balance);

        let total_supply_storage = storage.total_supply;
        let new_supply = total_supply_storage.read() - amount;
        total_supply_storage.write(new_supply);
    }

    /** ==========================================================
     * ================= OPTIMIZED HELPERS =========================
     * ======================================================== */

    /// Unconstrained calculation of shares conversion with constrained validation
    #[contract_library_method]
    unconstrained fn calculate_shares_unconstrained(
        assets: u128,
        total_assets: u128,
        total_supply: u128,
        round_up: bool,
    ) -> u128 {
        let mul_term = assets * (total_supply + 1);
        let denominator = (total_assets + 1);
        let mut shares = mul_term / denominator;
        if round_up & (mul_term % denominator > 0) {
            shares = shares + 1;
        }
        shares
    }

    /// Unconstrained calculation of assets conversion with constrained validation
    #[contract_library_method]
    unconstrained fn calculate_assets_unconstrained(
        shares: u128,
        total_assets: u128,
        total_supply: u128,
        round_up: bool,
    ) -> u128 {
        let mul_term = shares * (total_assets + 1);
        let denominator = (total_supply + 1);
        let mut assets = mul_term / denominator;
        if round_up & (mul_term % denominator > 0) {
            assets = assets + 1;
        }
        assets
    }

    /// Validate shares calculation (constrained)
    #[contract_library_method]
    fn validate_shares_calculation(
        assets: u128,
        total_assets: u128,
        total_supply: u128,
        shares: u128,
        round_up: bool,
    ) {
        let mul_term = assets * (total_supply + 1);
        let denominator = (total_assets + 1);
        let base_shares = mul_term / denominator;

        if round_up {
            let remainder = mul_term % denominator;
            let expected_shares = if remainder > 0 { base_shares + 1 } else { base_shares };
            assert(shares == expected_shares, "Invalid shares calculation");
        } else {
            assert(shares == base_shares, "Invalid shares calculation");
        }
    }

    /// Validate assets calculation (constrained)
    #[contract_library_method]
    fn validate_assets_calculation(
        shares: u128,
        total_assets: u128,
        total_supply: u128,
        assets: u128,
        round_up: bool,
    ) {
        let mul_term = shares * (total_assets + 1);
        let denominator = (total_supply + 1);
        let base_assets = mul_term / denominator;

        if round_up {
            let remainder = mul_term % denominator;
            let expected_assets = if remainder > 0 { base_assets + 1 } else { base_assets };
            assert(assets == expected_assets, "Invalid assets calculation");
        } else {
            assert(assets == base_assets, "Invalid assets calculation");
        }
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

        ContractInstanceRegistry::at(CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS)
            .update(ContractClassId::from_field(new_contract_class_id))
            .call(&mut context);
    }


    /** ==========================================================
     * ======================= VAULT =============================
     * ======================================================== */

    /* ====================== DEPOSIT ========================= */

    /// @notice Deposits the underlying asset from a public balance and receives shares to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param _nonce The nonce used for authwitness
    #[public]
    fn deposit_public_to_public(from: AztecAddress, to: AztecAddress, assets: u128, _nonce: Field) {
        // Inline _validate_from_public
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, from);
        }

        // Cache frequently accessed values
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_supply_storage = storage.total_supply;
        let current_total_supply = total_supply_storage.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Use unconstrained calculation then validate
        let shares = unsafe { calculate_shares_unconstrained(assets, total_assets, current_total_supply, false) };
        validate_shares_calculation(assets, total_assets, current_total_supply, shares, false);

        // Take the assets from the sender
        Token::at(asset_address)
            .transfer_public_to_public(from, this_address, assets, _nonce)
            .call(&mut context);

        // Inline _mint_to_public with cached values
        let to_balance_storage = storage.public_balances.at(to);
        let to_new_balance = to_balance_storage.read() + shares;
        to_balance_storage.write(to_new_balance);

        let new_supply = current_total_supply + shares;
        total_supply_storage.write(new_supply);
    }

    /// @notice Deposits the underlying asset from a public balance and receives shares to a private balance
    /// @dev The shares are calculated based on the ratio (total_supply + offset) / (total_assets + 1) minus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by. Any asset surplus is kept by the contract as yield.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares that should be minted to the recipient
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn deposit_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        let this_address = context.this_address();

        // Validate in public that `assets` is sufficient for the requested shares
        Token::at(this_address).validate_deposit_rate_internal(assets, shares).enqueue(&mut context);

        // Inline _mint_to_private
        storage.private_balances.at(to).add(to, shares).emit(encode_and_encrypt_note(&mut context, to));
        Token::at(this_address).increase_total_supply_internal(shares).enqueue(&mut context);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, this_address, assets, _nonce)
            .enqueue(&mut context);
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a private balance
    /// @dev The shares are calculated based on the ratio (total_supply + offset) / (total_assets + 1) minus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by. Any asset surplus is kept by the contract as yield.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares that should be minted to the recipient
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn deposit_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        let this_address = context.this_address();

        // Validate in public that `assets` is sufficient for the requested shares
        Token::at(this_address).validate_deposit_rate_internal(assets, shares).enqueue(&mut context);

        // Inline _mint_to_private
        storage.private_balances.at(to).add(to, shares).emit(encode_and_encrypt_note(&mut context, to));
        Token::at(this_address).increase_total_supply_internal(shares).enqueue(&mut context);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, this_address, assets, _nonce)
            .call(&mut context);
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn deposit_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<4>(&mut context, from);
        }

        let this_address = context.this_address();

        // Calculate and mint shares to the recipient in public
        Token::at(this_address).issue_from_assets_internal(to, assets).enqueue(&mut context);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, this_address, assets, _nonce)
            .call(&mut context);
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
    #[private]
    fn deposit_public_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        min_shares: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        // Inline _increase_private_balance with `min_shares`
        storage.private_balances.at(to).add(to, min_shares).emit(encode_and_encrypt_note(&mut context, to));

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Inline _initialize_transfer_commitment
        let this_address = context.this_address();
        let private_balances_at_to = storage.private_balances.at(to);
        let partial_note = UintNote::partial(
            to,
            private_balances_at_to.set.storage_slot,
            &mut context,
            to,
            this_address,
        );

        // Mint any outstanding shares without revealing the recipient and updates the shares total supply
        // Reverts if min_shares is greater than allowed
        Token::at(context.this_address())
            .settle_deposit_to_private_with_commitment_internal(
                partial_note.to_field(),
                assets,
                min_shares,
            )
            .enqueue(&mut context);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), assets, _nonce)
            .enqueue(&mut context);
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
    #[private]
    fn deposit_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        min_shares: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        // Inline _increase_private_balance with `min_shares`
        storage.private_balances.at(to).add(to, min_shares).emit(encode_and_encrypt_note(&mut context, to));

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to mint outstanding shares to the recipient in public
        // Inline _initialize_transfer_commitment
        let this_address = context.this_address();
        let private_balances_at_to = storage.private_balances.at(to);
        let partial_note = UintNote::partial(
            to,
            private_balances_at_to.set.storage_slot,
            &mut context,
            to,
            this_address,
        );

        // Mint any outstanding shares without revealing the recipient and updates the shares total supply
        // Reverts if min_shares is greater than allowed
        Token::at(context.this_address())
            .settle_deposit_to_private_with_commitment_internal(
                partial_note.to_field(),
                assets,
                min_shares,
            )
            .enqueue(&mut context);

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), assets, _nonce)
            .call(&mut context);
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
    #[public]
    fn issue_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_public
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, from);
        }

        // Cache frequently accessed values
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_supply_storage = storage.total_supply;
        let current_total_supply = total_supply_storage.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Use unconstrained calculation then validate
        let assets = unsafe { calculate_assets_unconstrained(shares, total_assets, current_total_supply, true) };
        validate_assets_calculation(shares, total_assets, current_total_supply, assets, true);

        // Take the assets from the sender
        Token::at(asset_address)
            .transfer_public_to_public(from, this_address, max_assets, _nonce)
            .call(&mut context);

        // Refund
        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            // Reimburse the sender with any excess assets sent
            Token::at(asset_address)
                .transfer_public_to_public(this_address, from, change, 0)
                .call(&mut context);
        }

        // Inline _mint_to_public
        let to_balance_storage = storage.public_balances.at(to);
        let to_new_balance = to_balance_storage.read() + shares;
        to_balance_storage.write(to_new_balance);

        let new_supply = current_total_supply + shares;
        total_supply_storage.write(new_supply);
    }

    /// @notice Issues exactly the requested shares to a private balance and receives the underlying asset from a public balance
    /// @dev max_assets is calculated based on the ratio (total_supply + offset) / (total_assets + 1) plus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn issue_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        // Take the assets from the sender
        Token::at(storage.asset.read())
            .transfer_public_to_public(from, context.this_address(), max_assets, _nonce)
            .enqueue(&mut context);

        // Validate the amount of assets transferred and send back any surplus
        Token::at(context.this_address())
            .settle_issuance_from_public_internal(from, shares, max_assets)
            .enqueue(&mut context);

        // Mint shares to the recipient
        // Inline _mint_to_private
        let this_address = context.this_address();
        storage.private_balances.at(to).add(to, shares).emit(encode_and_encrypt_note(&mut context, to));
        Token::at(this_address).increase_total_supply_internal(shares).enqueue(&mut context);
    }

    /// @notice Issues exactly the requested shares to a public balance and receives the underlying asset from a private balance
    /// @dev Any excess assets the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    ///      This excess amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn issue_private_to_public_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to refund excess assets to the sender in public
        let asset_commitment = Token::at(storage.asset.read())
            .initialize_transfer_commitment(from, context.this_address())
            .call(&mut context);

        // Take max_assets from the sender
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), max_assets, _nonce)
            .call(&mut context);

        // Validate max_assets in public and refund any surplus to the sender with a commitment
        Token::at(context.this_address())
            .settle_issuance_from_private_with_commitment(asset_commitment, shares, max_assets)
            .enqueue(&mut context);

        // Mint shares to recipient in public
        Token::at(context.this_address()).mint_to_public_internal(to, shares).enqueue(&mut context);
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
    #[private]
    fn issue_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to refund excess assets to the sender in public
        let asset_commitment = Token::at(storage.asset.read())
            .initialize_transfer_commitment(from, context.this_address())
            .call(&mut context);

        // Take max_assets from the sender
        Token::at(storage.asset.read())
            .transfer_private_to_public(from, context.this_address(), max_assets, _nonce)
            .call(&mut context);

        // Validate max_assets in public and refund any surplus to the sender with a commitment
        Token::at(context.this_address())
            .settle_issuance_from_private_with_commitment(asset_commitment, shares, max_assets)
            .enqueue(&mut context);

        // Mint shares to recipient in private
        // Inline _mint_to_private
        let this_address = context.this_address();
        storage.private_balances.at(to).add(to, shares).emit(encode_and_encrypt_note(&mut context, to));
        Token::at(this_address).increase_total_supply_internal(shares).enqueue(&mut context);
    }

    /* ====================== WITHDRAW ======================== */

    /// @notice Withdraws an amount of the underlying asset from a public balance to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param _nonce The nonce used for authwitness
    #[public]
    fn withdraw_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_public
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, from);
        }

        // Cache frequently accessed values
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_supply_storage = storage.total_supply;
        let current_total_supply = total_supply_storage.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Use unconstrained calculation then validate
        let shares = unsafe { calculate_shares_unconstrained(assets, total_assets, current_total_supply, true) };
        validate_shares_calculation(assets, total_assets, current_total_supply, shares, true);

        // Transfer the assets to the recipient
        Token::at(asset_address)
            .transfer_public_to_public(this_address, to, assets, 0)
            .call(&mut context);

        // Inline _burn_public
        let from_balance_storage = storage.public_balances.at(from);
        let from_new_balance = from_balance_storage.read() - shares;
        from_balance_storage.write(from_new_balance);

        let new_supply = current_total_supply - shares;
        total_supply_storage.write(new_supply);
    }

    /// @notice Withdraws an amount of the underlying asset from a public balance to a private balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn withdraw_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<4>(&mut context, from);
        }

        // Calculate and burn the sender's shares
        Token::at(context.this_address()).redeem_from_assets_internal(from, assets).enqueue(
            &mut context,
        );

        // Transfer the assets to the recipient in private
        Token::at(storage.asset.read())
            .transfer_public_to_private(context.this_address(), to, assets, 0)
            .call(&mut context);
    }

    /// @notice Withdraws an amount of the underlying asset from a private balance to a private balance
    /// @dev The shares are calculated with (total_supply + offset) / (total_assets + 1).
    ///      The ratio can only decrease or remain the same as time goes by. Any outstanding asset is kept by the contract as yield.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param shares The amount of shares to burn
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn withdraw_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        // Validate that the shares-assets ratio is correct
        Token::at(context.this_address()).validate_withdrawal_rate_internal(assets, shares).enqueue(
            &mut context,
        );

        // Burn shares from the sender in private
        // Inline _burn_private
        let this_address = context.this_address();
        let private_balances_at_from = storage.private_balances.at(from);
        let subtracted = private_balances_at_from.try_sub(shares, INITIAL_TRANSFER_CALL_MAX_NOTES);
        assert(subtracted > 0, "Balance too low");

        let change = if subtracted >= shares {
            subtracted - shares
        } else {
            let remaining = shares - subtracted;
            Token::at(this_address).recurse_subtract_balance_internal(from, remaining).call(&mut context)
        };

        if change > 0 {
            private_balances_at_from.add(from, change).emit(encode_and_encrypt_note(&mut context, from));
        }

        Token::at(this_address).decrease_total_supply_internal(shares).enqueue(&mut context);

        // Transfer the assets to the recipient in private
        Token::at(storage.asset.read())
            .transfer_public_to_private(context.this_address(), to, assets, 0)
            .call(&mut context);
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
    #[private]
    fn withdraw_private_to_public_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        max_shares: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to refund excess shares to the sender in public
        // Inline _initialize_transfer_commitment
        let this_address = context.this_address();
        let private_balances_at_from = storage.private_balances.at(from);
        let partial_note = UintNote::partial(
            from,
            private_balances_at_from.set.storage_slot,
            &mut context,
            from,
            this_address,
        );

        // Burn shares from the sender in private
        // Inline _decrease_private_balance
        let private_balances_at_from = storage.private_balances.at(from);
        let subtracted = private_balances_at_from.try_sub(max_shares, INITIAL_TRANSFER_CALL_MAX_NOTES);
        assert(subtracted > 0, "Balance too low");

        let change = if subtracted >= max_shares {
            subtracted - max_shares
        } else {
            let remaining = max_shares - subtracted;
            Token::at(this_address).recurse_subtract_balance_internal(from, remaining).call(&mut context)
        };

        if change > 0 {
            private_balances_at_from.add(from, change).emit(encode_and_encrypt_note(&mut context, from));
        }

        // Burn the correct amount of shares
        // Any excess amount of shares is sent back to the sender via commitment
        // Reverts if the amount of shares required is greater than max_shares
        Token::at(context.this_address())
            .settle_withdrawal_with_commitment_internal(partial_note.to_field(), assets, max_shares)
            .enqueue(&mut context);

        // Transfer the assets to the sender
        Token::at(storage.asset.read())
            .transfer_public_to_public(context.this_address(), to, assets, 0)
            .enqueue(&mut context);
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
    #[private]
    fn withdraw_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        max_shares: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed
        // Initialize commitment that allows to refund excess shares to the sender in public
        // Inline _initialize_transfer_commitment
        let this_address = context.this_address();
        let private_balances_at_from = storage.private_balances.at(from);
        let partial_note = UintNote::partial(
            from,
            private_balances_at_from.set.storage_slot,
            &mut context,
            from,
            this_address,
        );

        // Burn shares from the sender in private
        // Inline _decrease_private_balance
        let private_balances_at_from = storage.private_balances.at(from);
        let subtracted = private_balances_at_from.try_sub(max_shares, INITIAL_TRANSFER_CALL_MAX_NOTES);
        assert(subtracted > 0, "Balance too low");

        let change = if subtracted >= max_shares {
            subtracted - max_shares
        } else {
            let remaining = max_shares - subtracted;
            Token::at(this_address).recurse_subtract_balance_internal(from, remaining).call(&mut context)
        };

        if change > 0 {
            private_balances_at_from.add(from, change).emit(encode_and_encrypt_note(&mut context, from));
        }

        // Burn the correct amount of shares
        // Any excess amount of shares is sent back to the sender via commitment
        // Reverts if the amount of shares required is greater than max_shares
        Token::at(context.this_address())
            .settle_withdrawal_with_commitment_internal(partial_note.to_field(), assets, max_shares)
            .enqueue(&mut context);

        // Transfer the assets to the recipient in private
        Token::at(storage.asset.read())
            .transfer_public_to_private(context.this_address(), to, assets, 0)
            .call(&mut context);
    }

    /* ======================= REDEEM ========================= */

    /// @notice Redeems an amount of the shares from a public balance to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param _nonce The nonce used for authwitness
    #[public]
    fn redeem_public_to_public(from: AztecAddress, to: AztecAddress, shares: u128, _nonce: Field) {
        // Inline _validate_from_public
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, from);
        }

        // Cache frequently accessed values
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_supply_storage = storage.total_supply;
        let current_total_supply = total_supply_storage.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Use unconstrained calculation then validate
        let assets = unsafe { calculate_assets_unconstrained(shares, total_assets, current_total_supply, false) };
        validate_assets_calculation(shares, total_assets, current_total_supply, assets, false);

        // Transfer the assets to the recipient
        Token::at(asset_address)
            .transfer_public_to_public(this_address, to, assets, 0)
            .call(&mut context);

        // Inline _burn_public
        let from_balance_storage = storage.public_balances.at(from);
        let from_new_balance = from_balance_storage.read() - shares;
        from_balance_storage.write(from_new_balance);

        let new_supply = current_total_supply - shares;
        total_supply_storage.write(new_supply);
    }

    /// @notice Redeems an amount of the shares from a private balance to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param _nonce The nonce used for authwitness
    #[private]
    fn redeem_private_to_public(from: AztecAddress, to: AztecAddress, shares: u128, _nonce: Field) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<4>(&mut context, from);
        }

        // Burn shares and redeem public assets
        Token::at(context.this_address()).settle_redemption_to_public_internal(to, shares).enqueue(
            &mut context,
        );

        // Burn shares from the sender in private
        // Inline _burn_private
        let this_address = context.this_address();
        let private_balances_at_from = storage.private_balances.at(from);
        let subtracted = private_balances_at_from.try_sub(shares, INITIAL_TRANSFER_CALL_MAX_NOTES);
        assert(subtracted > 0, "Balance too low");

        let change = if subtracted >= shares {
            subtracted - shares
        } else {
            let remaining = shares - subtracted;
            Token::at(this_address).recurse_subtract_balance_internal(from, remaining).call(&mut context)
        };

        if change > 0 {
            private_balances_at_from.add(from, change).emit(encode_and_encrypt_note(&mut context, from));
        }

        Token::at(this_address).decrease_total_supply_internal(shares).enqueue(&mut context);
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
    #[private]
    fn redeem_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        min_assets: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to transfer outstanding assets to the recipient in public
        let asset_commitment = Token::at(storage.asset.read())
            .initialize_transfer_commitment(to, context.this_address())
            .call(&mut context);

        // Transfers any outstanding assets without revealing the recipient
        // Reverts if min_assets is greater than allowed
        Token::at(context.this_address())
            .settle_redemption_to_private_with_commitment(asset_commitment, shares, min_assets)
            .enqueue(&mut context);

        // Transfer min_assets to the recipient
        Token::at(storage.asset.read())
            .transfer_public_to_private(context.this_address(), to, min_assets, 0)
            .call(&mut context);

        // Burn shares from the sender in private
        // Inline _burn_private
        let this_address = context.this_address();
        let private_balances_at_from = storage.private_balances.at(from);
        let subtracted = private_balances_at_from.try_sub(shares, INITIAL_TRANSFER_CALL_MAX_NOTES);
        assert(subtracted > 0, "Balance too low");

        let change = if subtracted >= shares {
            subtracted - shares
        } else {
            let remaining = shares - subtracted;
            Token::at(this_address).recurse_subtract_balance_internal(from, remaining).call(&mut context)
        };

        if change > 0 {
            private_balances_at_from.add(from, change).emit(encode_and_encrypt_note(&mut context, from));
        }

        Token::at(this_address).decrease_total_supply_internal(shares).enqueue(&mut context);
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
    #[private]
    fn redeem_public_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        min_assets: u128,
        _nonce: Field,
    ) {
        // Inline _validate_from_private
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit::<5>(&mut context, from);
        }

        // TODO (optimization): partial note logs and validity_commitment nullifier are not needed (?)
        // Initialize commitment that allows to transfer outstanding assets to the recipient in public
        let asset_commitment = Token::at(storage.asset.read())
            .initialize_transfer_commitment(to, context.this_address())
            .call(&mut context);

        // Transfers any outstanding assets without revealing the recipient
        // Reverts if min_assets is greater than allowed
        Token::at(context.this_address())
            .settle_redemption_to_private_with_commitment(asset_commitment, shares, min_assets)
            .enqueue(&mut context);

        // Transfer min_assets to the recipient
        Token::at(storage.asset.read())
            .transfer_public_to_private(context.this_address(), to, min_assets, 0)
            .call(&mut context);

        // Burn the shares being redeemed
        Token::at(context.this_address()).burn_public_internal(from, shares).enqueue(&mut context);
    }

    /** ==========================================================
     * ==================== VAULT INTERNALS ======================
     * ======================================================== */

    /// @notice Burns shares held in public for a given amount of assets
    /// @param from The address of the sender
    /// @param assets The amount of assets to burn shares for
    #[public]
    #[internal]
    fn redeem_from_assets_internal(from: AztecAddress, assets: u128) {
        // Inline _total_assets
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Inline _convert_to_shares with ROUND_UP
        let total_supply_storage = storage.total_supply;
        let mul_term = assets * (total_supply_storage.read() + 1);
        let denominator = (total_assets + 1);
        let mut shares = mul_term / denominator;
        if (mul_term % denominator > 0) {
            shares = shares + 1;
        }

        // Inline _burn_public
        let from_balance_storage = storage.public_balances.at(from);
        let from_new_balance = from_balance_storage.read() - shares;
        from_balance_storage.write(from_new_balance);

        let new_supply = total_supply_storage.read() - shares;
        total_supply_storage.write(new_supply);
    }

    /// @notice Validates that the requested shares amount is valid for the given assets
    /// @param assets The amount of assets being withdrawn
    /// @param shares The amount of shares being burned
    #[public]
    #[internal]
    fn validate_withdrawal_rate_internal(assets: u128, shares: u128) {
        // Inline _total_assets
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Inline _convert_to_shares with ROUND_UP
        let mul_term = assets * (storage.total_supply.read() + 1);
        let denominator = (total_assets + 1);
        let mut min_shares = mul_term / denominator;
        if (mul_term % denominator > 0) {
            min_shares = min_shares + 1;
        }

        assert(min_shares <= shares, "Insufficient shares burnt");
    }

    /// @notice Withdraws assets to a public balance for a given amount of shares
    /// @param to The address of the recipient
    /// @param shares The amount of shares being redeemed
    #[public]
    #[internal]
    fn settle_redemption_to_public_internal(to: AztecAddress, shares: u128) {
        // Inline _total_assets
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Inline _convert_to_assets with ROUND_DOWN
        let mul_term = shares * (total_assets + 1);
        let denominator = (storage.total_supply.read() + 1);
        let assets = mul_term / denominator;

        Token::at(asset_address)
            .transfer_public_to_public(this_address, to, assets, 0)
            .call(&mut context);
    }

    /// @notice Mints shares to a public balance for a given amount of assets
    /// @param to The address of the recipient
    /// @param assets The amount of assets being deposited
    #[public]
    #[internal]
    fn issue_from_assets_internal(to: AztecAddress, assets: u128) {
        // Inline _total_assets
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Inline _convert_to_shares with ROUND_DOWN
        let total_supply_storage = storage.total_supply;
        let mul_term = assets * (total_supply_storage.read() + 1);
        let denominator = (total_assets + 1);
        let shares = mul_term / denominator;

        // Inline _mint_to_public
        let to_balance_storage = storage.public_balances.at(to);
        let to_new_balance = to_balance_storage.read() + shares;
        to_balance_storage.write(to_new_balance);

        let new_supply = total_supply_storage.read() + shares;
        total_supply_storage.write(new_supply);
    }

    /// @notice Validates that the requested shares amount is valid for the deposited assets
    /// @param assets The amount of assets being deposited
    /// @param shares The amount of shares being issued
    #[public]
    #[internal]
    fn validate_deposit_rate_internal(assets: u128, shares: u128) {
        // Inline _total_assets
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Inline _convert_to_shares with ROUND_DOWN
        let mul_term = assets * (storage.total_supply.read() + 1);
        let denominator = (total_assets + 1);
        let max_shares = mul_term / denominator;

        assert(shares <= max_shares, "Too many shares requested");
    }

    /// @notice Decreases shares total supply and refunds excess shares via commitment
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of assets being withdrawn
    /// @param max_shares The maximum amount of shares that should be redeemed
    #[public]
    #[internal]
    fn settle_withdrawal_with_commitment_internal(
        commitment: Field,
        assets: u128,
        max_shares: u128,
    ) {
        // Inline _total_assets
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Inline _convert_to_shares with ROUND_UP
        let total_supply_storage = storage.total_supply;
        let mul_term = assets * (total_supply_storage.read() + 1);
        let denominator = (total_assets + 1);
        let mut shares = mul_term / denominator;
        if (mul_term % denominator > 0) {
            shares = shares + 1;
        }

        let surplus = max_shares - shares; // Reverts with underflow if invalid
        if surplus > 0 {
            // Inline _increase_commitment_balance
            PartialUintNote::from_field(commitment).complete(&mut context, this_address, surplus);
        }

        // Inline _decrease_total_supply
        let new_supply = total_supply_storage.read() - shares;
        total_supply_storage.write(new_supply);
    }

    /// @notice Increases shares total supply and issues outstanding shares via commitment
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of assets being deposited
    /// @param min_shares The minimum amount of shares that should be issued
    #[public]
    #[internal]
    fn settle_deposit_to_private_with_commitment_internal(
        commitment: Field,
        assets: u128,
        min_shares: u128,
    ) {
        // Inline _total_assets
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Inline _convert_to_shares with ROUND_DOWN
        let total_supply_storage = storage.total_supply;
        let mul_term = assets * (total_supply_storage.read() + 1);
        let denominator = (total_assets + 1);
        let max_shares = mul_term / denominator;

        let outstanding_shares = max_shares - min_shares; // Reverts with underflow if invalid
        if outstanding_shares > 0 {
            // Inline _increase_commitment_balance
            PartialUintNote::from_field(commitment).complete(&mut context, this_address, outstanding_shares);
        }

        // Inline _increase_total_supply
        let new_supply = total_supply_storage.read() + max_shares;
        total_supply_storage.write(new_supply);
    }

    /// @notice Refunds excess assets to the sender via commitment while validating the shares amount requested
    /// @param asset_commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of shares being issued
    /// @param max_assets The maximum amount of assets that should be deposited
    #[public]
    #[internal]
    fn settle_issuance_from_private_with_commitment(
        asset_commitment: Field,
        shares: u128,
        max_assets: u128,
    ) {
        // Inline _total_assets
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Inline _convert_to_assets with ROUND_UP
        let adjusted_total_assets = total_assets - max_assets;
        let current_total_supply = storage.total_supply.read();
        let assets = unsafe { calculate_assets_unconstrained(shares, adjusted_total_assets, current_total_supply, true) };
        validate_assets_calculation(shares, adjusted_total_assets, current_total_supply, assets, true);

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            Token::at(asset_address)
                .transfer_public_to_commitment(this_address, asset_commitment, change, 0)
                .call(&mut context);
        }
    }

    /// @notice Validates share redemption rate and withdraws any outstanding assets via commitment
    /// @param asset_commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of shares being redeemed
    /// @param min_assets The minimum amount of assets that should be withdrawn
    #[public]
    #[internal]
    fn settle_redemption_to_private_with_commitment(
        asset_commitment: Field,
        shares: u128,
        min_assets: u128,
    ) {
        // Inline _total_assets
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Inline _convert_to_assets with ROUND_DOWN
        let current_total_supply = storage.total_supply.read();
        let assets = unsafe { calculate_assets_unconstrained(shares, total_assets, current_total_supply, false) };
        validate_assets_calculation(shares, total_assets, current_total_supply, assets, false);

        let outstanding_assets = assets - min_assets; // Reverts with underflow if invalid
        if outstanding_assets > 0 {
            Token::at(asset_address)
                .transfer_public_to_commitment(
                    this_address,
                    asset_commitment,
                    outstanding_assets,
                    0,
                )
                .call(&mut context);
        }
    }

    /// @notice Validates issuance rate and refunds excess assets being deposited from a public balance
    /// @param from The address of the sender
    /// @param shares The amount of shares being issued
    /// @param max_assets The maximum amount of assets that should be deposited
    #[public]
    #[internal]
    fn settle_issuance_from_public_internal(from: AztecAddress, shares: u128, max_assets: u128) {
        // Inline _total_assets
        let this_address = context.this_address();
        let asset_address = storage.asset.read();
        let total_assets = Token::at(asset_address).balance_of_public(this_address).view(&mut context);

        // Inline _convert_to_assets with ROUND_UP
        let adjusted_total_assets = total_assets - max_assets;
        let current_total_supply = storage.total_supply.read();
        let assets = unsafe { calculate_assets_unconstrained(shares, adjusted_total_assets, current_total_supply, true) };
        validate_assets_calculation(shares, adjusted_total_assets, current_total_supply, assets, true);

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            Token::at(asset_address)
                .transfer_public_to_public(this_address, from, change, 0)
                .call(&mut context);
        }
    }

}
