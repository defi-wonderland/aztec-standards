pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract Vault {
    use aztec::{
        authwit::auth::{
            assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
        },
        context::PrivateContext,
        macros::{functions::{external, initializer, internal, only_self, view}, storage::storage},
        protocol::{
            address::AztecAddress, constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            contract_class_id::ContractClassId, traits::FromField,
        },
        state_vars::PublicImmutable,
    };
    use contract_instance_registry::ContractInstanceRegistry;
    use token_contract::Token;

    // Rounding direction that the vault uses to calculate shares and assets
    global ROUND_DOWN: bool = false;
    global ROUND_UP: bool = true;

    // Maximum value for a u128 (2**128 - 1)
    global MAX_U128_VALUE: u128 = 340282366920938463463374607431768211455;

    /// @param admin The address with permission to set the shares token (one-time setup)
    /// @param asset The underlying asset token address
    /// @param shares The shares token address (minter must be this vault)
    /// @param vault_offset The offset used to prevent inflation attacks
    /// @param upgrade_authority The address with permission to upgrade the contract
    #[storage]
    struct Storage<Context> {
        admin: PublicImmutable<AztecAddress, Context>,
        asset: PublicImmutable<AztecAddress, Context>,
        shares: PublicImmutable<AztecAddress, Context>,
        vault_offset: PublicImmutable<u128, Context>,
        upgrade_authority: PublicImmutable<AztecAddress, Context>,
    }

    /// @notice Initializes the vault with asset, offset, and configuration
    /// @dev The admin must call set_shares() after deploying the shares token with this vault as minter.
    ///      The vault address can be precomputed before shares exists since shares is not a constructor arg.
    ///      This 2-step deployment exists because contract instance publishing is private-only, so a public
    ///      factory cannot deploy and wire both contracts atomically. Once public instance registration is
    ///      supported, this can be simplified to a single-step deployment.
    ///      See: https://github.com/AztecProtocol/aztec-packages/issues/20771
    /// @param admin The address with permission to set the shares token (one-time setup)
    /// @param asset The underlying asset token address
    /// @param vault_offset The offset used to prevent inflation attacks (typically 1)
    /// @param upgrade_authority The address of the upgrade authority (zero address if not upgradeable)
    #[external("public")]
    #[initializer]
    fn constructor(
        admin: AztecAddress,
        asset: AztecAddress,
        vault_offset: u128,
        upgrade_authority: AztecAddress,
    ) {
        assert(vault_offset > 0, "vault_offset must be greater than 0");
        self.storage.admin.initialize(admin);
        self.storage.asset.initialize(asset);
        self.storage.vault_offset.initialize(vault_offset);
        self.storage.upgrade_authority.initialize(upgrade_authority);
    }

    /// @notice Sets the shares token address (one-time, admin-only, immutable after set)
    /// @dev Must be called after deploying the shares token with this vault as minter.
    ///      PublicImmutable.initialize() ensures this can only ever be set once -- any subsequent
    ///      call will revert. All vault operations read shares via PublicImmutable.read() which
    ///      reverts if shares has not been initialized, so the vault is inoperable until this is called.
    /// @param shares The shares token address (minter must be this vault)
    #[external("public")]
    fn set_shares_token(shares: AztecAddress) {
        let admin = self.storage.admin.read();
        assert(self.msg_sender().eq(admin), "caller is not admin");
        self.storage.shares.initialize(shares);
    }

    /// @notice Sets the shares token and makes an initial deposit for inflation-attack protection
    /// @dev Must be called after deploying the shares token with this vault as minter.
    ///      PublicImmutable.initialize() ensures this can only ever be set once -- any subsequent
    ///      call will revert. All vault operations read shares via PublicImmutable.read() which
    ///      reverts if shares has not been initialized, so the vault is inoperable until this is called.
    /// @param shares The shares token address (minter must be this vault)
    /// @param initial_deposit The initial deposit amount of the asset
    /// @param depositor The address of the initial depositor of the assets
    /// @param nonce The nonce used for authwitness for the transfer of the initial deposit
    #[external("public")]
    fn set_shares_token_with_initial_deposit(
        shares: AztecAddress,
        initial_deposit: u128,
        depositor: AztecAddress,
        nonce: Field,
    ) {
        let admin = self.storage.admin.read();
        assert(self.msg_sender().eq(admin), "caller is not admin");
        self.storage.shares.initialize(shares);

        // Caller deposits assets, shares are minted to this contract and are permanently locked.
        let from = depositor;
        let to = self.address;

        // Assets could be donated to the vault's precomputed address before deployment, but such assets are
        // ignored at this point to ensure the asset<>share conversion is 1:1 for the initial deposit.
        let total_assets: u128 = 0;
        let total_supply: u128 = 0;
        let vault_offset = self.storage.vault_offset.read();

        // Calculate shares to mint for the initial deposit.
        let deposit_shares = _convert_to_shares(
            initial_deposit,
            total_assets,
            total_supply,
            vault_offset,
            ROUND_DOWN,
        );

        // Transfer the assets from the sender to the vault
        let asset_token = self.storage.asset.read();
        self.call(Token::at(asset_token).transfer_public_to_public(from, to, initial_deposit, nonce));

        // Mint shares to this contract address (permanently locked)
        self.call(Token::at(shares).mint_to_public(to, deposit_shares));
    }

    /** ==========================================================
     * ========================= DEPOSIT =========================
     * ======================================================== */

    // ## Note on ARC-403 assets
    // ARC-403 hooks may execute user code before a transfer (sender hook) or after it (recipient hook).
    // Users can therefore use hooks to reenter the vault, either when they send asset tokens in deposit and issue
    // functions or when they receive asset tokens in withdraw and redeem functions.
    //
    // To keep the contract safe, reentrancy should not happen at half-updated states:
    //  - Assets should be transferred into the vault BEFORE minting shares. Reentrancy would only happen before any
    //    balance is updated.
    //  - Assets should be transferred out of the vault AFTER burning shares. Reentrancy would only happen after all
    //    balances are updated.

    /// @notice Deposits the underlying asset from a public balance and receives shares to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param nonce The nonce used for authwitness
    #[external("public")]
    fn deposit_public_to_public(from: AztecAddress, to: AztecAddress, assets: u128, nonce: Field) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        self.internal._validate_from_public(from);

        // Calculate shares to mint
        let total_assets = self.internal._total_assets();
        let total_supply = self.internal._total_supply_of_shares();
        let vault_offset = self.storage.vault_offset.read();
        let shares =
            _convert_to_shares(assets, total_assets, total_supply, vault_offset, ROUND_DOWN);

        // Order matters: transfer before minting to neutralize ARC-403 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(asset_token).transfer_public_to_public(
            from,
            self.address,
            assets,
            nonce,
        ));

        // Mint shares to the recipient
        self.call(Token::at(shares_token).mint_to_public(to, shares));
    }

    /// @notice Deposits the underlying asset from a public balance and receives shares to a private balance
    /// @dev The shares are calculated based on the ratio (total_supply + offset) / (total_assets + 1) minus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by. Any asset excess is kept by the contract as yield.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares that should be minted to the recipient
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        nonce: Field,
    ) {
        let shares_token = self.storage.shares.read();
        _validate_from_private::<5>(self.context, from);

        // Validate in public that `assets` is sufficient for the requested shares
        // Order matters: enqueue settlement first so asset transfer executes before shares total_supply increase
        self.enqueue_self.settle_deposit_public_to_private_internal(from, assets, shares, nonce);

        // Mint shares to the recipient's private balance
        self.call(Token::at(shares_token).mint_to_private(to, shares));
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a private balance
    /// @dev The shares are calculated based on the ratio (total_supply + offset) / (total_assets + 1) minus any acceptable slippage.
    ///      The ratio can only decrease or remain the same as time goes by. Any asset excess is kept by the contract as yield.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares that should be minted to the recipient
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        _validate_from_private::<5>(self.context, from);

        // Order matters: transfer before minting to neutralize ARC-403 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(asset_token).transfer_private_to_public(
            from,
            self.address,
            assets,
            nonce,
        ));

        // Mint shares to the recipient's private balance
        self.call(Token::at(shares_token).mint_to_private(to, shares));

        // Validate in public that `assets` is sufficient for the requested shares
        self.enqueue_self.settle_deposit_private_to_private_internal(assets, shares);
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        _validate_from_private::<4>(self.context, from);

        // Order matters: transfer before minting to neutralize ARC-403 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(asset_token).transfer_private_to_public(
            from,
            self.address,
            assets,
            nonce,
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
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_public_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        min_shares: u128,
        nonce: Field,
    ) {
        let shares_token = self.storage.shares.read();
        _validate_from_private::<5>(self.context, from);

        // Initialize commitment on the shares token that allows to mint outstanding shares to the recipient in public
        let partial_note = self.call(Token::at(shares_token)
            .initialize_transfer_commitment(to, self.address));

        // Mint any outstanding shares without revealing the recipient and updates the shares total supply
        // Reverts if min_shares is greater than allowed
        // Order matters: enqueue settlement first so asset transfer executes before shares total_supply increase
        self.enqueue_self.settle_deposit_public_to_private_exact_internal(
            from,
            partial_note,
            assets,
            min_shares,
            nonce,
        );

        // Mint min_shares to the recipient's private balance
        self.call(Token::at(shares_token).mint_to_private(to, min_shares));
    }

    /// @notice Deposits the underlying asset from a private balance and receives shares to a private balance
    /// @dev min_shares is the amount of shares that will be minted immediately in private.
    ///      Any additional shares the recipient is entitled to, will be minted through a commitment once the call is executed publicly.
    ///      This additional amount can only be known at public execution.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to deposit
    /// @param min_shares The amount of shares that should be minted to the recipient in private
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn deposit_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        min_shares: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        _validate_from_private::<5>(self.context, from);

        // Initialize commitment on the shares token that allows to mint outstanding shares to the recipient in public
        let partial_note = self.call(Token::at(shares_token)
            .initialize_transfer_commitment(to, self.address));

        // Order matters: transfer before minting to neutralize ARC-403 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(asset_token).transfer_private_to_public(
            from,
            self.address,
            assets,
            nonce,
        ));

        // Mint min_shares to the recipient's private balance
        self.call(Token::at(shares_token).mint_to_private(to, min_shares));

        // Mint any outstanding shares without revealing the recipient and updates the shares total supply
        // Reverts if min_shares is greater than allowed
        self.enqueue_self.settle_deposit_private_to_private_exact_internal(
            partial_note,
            assets,
            min_shares,
        );
    }

    /** ==========================================================
     * ========================== ISSUE ==========================
     * ======================================================== */

    /// @notice Issues exactly the requested shares to a public balance and receives the underlying asset from a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param nonce The nonce used for authwitness
    #[external("public")]
    fn issue_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        self.internal._validate_from_public(from);

        // Calculate assets required
        let total_assets = self.internal._total_assets();
        let total_supply = self.internal._total_supply_of_shares();
        let vault_offset = self.storage.vault_offset.read();
        let assets = _convert_to_assets(shares, total_assets, total_supply, vault_offset, ROUND_UP);

        // Order matters: transfer before minting to neutralize ARC-403 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(asset_token).transfer_public_to_public(
            from,
            self.address,
            max_assets,
            nonce,
        ));

        // Refund before minting to prevent inflated total_assets during ARC-403 `tokens_received` hook
        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            self.call(Token::at(asset_token).transfer_public_to_public(
                self.address,
                from,
                change,
                0,
            ));
        }

        // Mint shares to the recipient (after refund so vault balance is correct when ARC-403 hook fires)
        self.call(Token::at(shares_token).mint_to_public(to, shares));
    }

    /// @notice Issues exactly the requested shares to a private balance and receives the underlying asset from a public balance
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn issue_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        nonce: Field,
    ) {
        let shares_token = self.storage.shares.read();
        _validate_from_private::<5>(self.context, from);

        // Validate the amount of assets transferred and send back any excess
        // Order matters: enqueue settlement first so asset transfer executes before shares total_supply increase
        self.enqueue_self.settle_issue_public_to_private_internal(from, shares, max_assets, nonce);

        // Mint shares to the recipient's private balance
        self.call(Token::at(shares_token).mint_to_private(to, shares));
    }

    /// @notice Issues exactly the requested shares to a public balance and receives the underlying asset from a private balance
    /// @dev Any excess assets the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn issue_private_to_public_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        _validate_from_private::<5>(self.context, from);

        // Initialize commitment on the asset token that allows to refund excess assets to the sender in public
        let asset_commitment = self.call(Token::at(asset_token)
            .initialize_transfer_commitment(from, self.address));

        // Order matters: transfer before minting to neutralize ARC-403 reentrancy via the `tokens_to_send` hook.
        // Take max_assets from the sender
        self.call(Token::at(asset_token).transfer_private_to_public(
            from,
            self.address,
            max_assets,
            nonce,
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
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to issue
    /// @param max_assets The maximum amount of assets that should be deposited
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn issue_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        _validate_from_private::<5>(self.context, from);

        // Initialize commitment on the asset token that allows to refund excess assets to the sender in public
        let asset_commitment = self.call(Token::at(asset_token)
            .initialize_transfer_commitment(from, self.address));

        // Order matters: transfer before minting to neutralize ARC-403 reentrancy via the `tokens_to_send` hook.
        // Take max_assets from the sender
        self.call(Token::at(asset_token).transfer_private_to_public(
            from,
            self.address,
            max_assets,
            nonce,
        ));

        // Mint shares to the recipient's private balance
        self.call(Token::at(shares_token).mint_to_private(to, shares));

        // Validate max_assets in public and refunds any excess to the sender with a commitment
        self.enqueue_self.settle_issue_private_to_private_exact_internal(
            asset_commitment,
            shares,
            max_assets,
        );
    }

    /** ==========================================================
     * ======================== WITHDRAW =========================
     * ======================================================== */

    /// @notice Withdraws an amount of the underlying asset from a public balance to a public balance
    /// @dev User must provide a public authwit on the shares token authorizing this vault to burn shares
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param nonce The nonce used for authwitness
    #[external("public")]
    fn withdraw_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        self.internal._validate_from_public(from);

        // Calculate shares to burn
        let total_assets = self.internal._total_assets();
        let total_supply = self.internal._total_supply_of_shares();
        let vault_offset = self.storage.vault_offset.read();
        let shares = _convert_to_shares(assets, total_assets, total_supply, vault_offset, ROUND_UP);

        // Order matters: burn before transferring to neutralize ARC-403 reentrancy via the `tokens_received` hook.
        // Burn the sender's shares on the shares token
        self.call(Token::at(shares_token).burn_public(from, shares, nonce));

        // Transfer the assets to the recipient
        self.call(Token::at(asset_token).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Withdraws an amount of the underlying asset from a public balance to a private balance
    /// @dev User must provide a public authwit on the shares token authorizing this vault to burn shares
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        _validate_from_private::<4>(self.context, from);

        // Order matters: burn after calculating shares in public to neutralize ARC-403 reentrancy via the `tokens_received` hook.
        // Calculate and burn the sender's shares
        self.enqueue_self.settle_withdraw_public_to_private_internal(from, assets, nonce);

        // Transfer the assets to the recipient in private
        self.call(Token::at(asset_token).transfer_public_to_private(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Withdraws an amount of the underlying asset from a private balance to a private balance
    /// @dev The shares are calculated with (total_supply + offset) / (total_assets + 1).
    ///      User must provide a private authwit on the shares token authorizing this vault to burn shares.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of assets to withdraw
    /// @param shares The amount of shares to burn
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        shares: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        _validate_from_private::<5>(self.context, from);

        // Burn shares from the sender's private balance on the shares token
        self.call(Token::at(shares_token).burn_private(from, shares, nonce));

        // Order matters: transfer after burning to neutralize ARC-403 reentrancy via the `tokens_received` hook.
        // Validate that the shares-assets ratio is correct
        self.enqueue_self.settle_withdraw_private_to_private_internal(assets, shares);

        // Transfer the assets to the recipient in private
        self.call(Token::at(asset_token).transfer_public_to_private(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Withdraws an amount of the underlying asset from a private balance to a public balance
    /// @dev max_shares is the amount of shares that will be burnt immediately in private.
    ///      Any excess shares the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    ///      User must provide a private authwit on the shares token authorizing this vault to burn shares.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of underlying asset to withdraw
    /// @param max_shares The maximum amount of shares to burn
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_private_to_public_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        max_shares: u128,
        nonce: Field,
    ) {
        let shares_token = self.storage.shares.read();
        _validate_from_private::<5>(self.context, from);

        // Initialize commitment on the shares token that allows to refund excess shares to the sender in public
        let partial_note = self.call(Token::at(shares_token)
            .initialize_transfer_commitment(from, self.address));

        // Burn max_shares from the sender's private balance on the shares token
        self.call(Token::at(shares_token).burn_private(from, max_shares, nonce));

        // Burn the correct amount of shares
        // Any excess amount of shares is sent back to the sender via commitment
        // Reverts if the amount of shares required is greater than max_shares
        self.enqueue_self.settle_withdraw_private_to_public_exact_internal(
            partial_note,
            assets,
            max_shares,
            to,
        );
    }

    /// @notice Withdraws an amount of the underlying asset from a private balance to a private balance
    /// @dev max_shares is the amount of shares that will be burnt immediately in private.
    ///      Any excess shares the sender has transferred in private, will be returned to the sender through a commitment once the call is executed publicly.
    ///      User must provide a private authwit on the shares token authorizing this vault to burn shares.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param assets The amount of underlying asset to withdraw
    /// @param max_shares The maximum amount of shares to burn
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn withdraw_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        max_shares: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        _validate_from_private::<5>(self.context, from);

        // Initialize commitment on the shares token that allows to refund excess shares to the sender in public
        let partial_note = self.call(Token::at(shares_token)
            .initialize_transfer_commitment(from, self.address));

        // Burn max_shares from the sender's private balance on the shares token
        self.call(Token::at(shares_token).burn_private(from, max_shares, nonce));

        // Order matters: transfer after burning to neutralize ARC-403 reentrancy via the `tokens_received` hook.
        // Burn the correct amount of shares
        // Any excess amount of shares is sent back to the sender via commitment
        // Reverts if the amount of shares required is greater than max_shares
        self.enqueue_self.settle_withdraw_private_to_private_exact_internal(
            partial_note,
            assets,
            max_shares,
        );

        // Transfer the assets to the recipient in private
        self.call(Token::at(asset_token).transfer_public_to_private(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /** ==========================================================
     * ========================= REDEEM ==========================
     * ======================================================== */

    /// @notice Redeems an amount of the shares from a public balance to a public balance
    /// @dev User must provide a public authwit on the shares token authorizing this vault to burn shares
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param nonce The nonce used for authwitness
    #[external("public")]
    fn redeem_public_to_public(from: AztecAddress, to: AztecAddress, shares: u128, nonce: Field) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        self.internal._validate_from_public(from);

        // Calculate assets to redeem
        let total_assets = self.internal._total_assets();
        let total_supply = self.internal._total_supply_of_shares();
        let vault_offset = self.storage.vault_offset.read();
        let assets =
            _convert_to_assets(shares, total_assets, total_supply, vault_offset, ROUND_DOWN);

        // Order matters: burn before transferring to neutralize ARC-403 reentrancy via the `tokens_received` hook.
        // Burn the sender's shares on the shares token
        self.call(Token::at(shares_token).burn_public(from, shares, nonce));

        // Transfer the assets to the recipient
        self.call(Token::at(asset_token).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Redeems an amount of the shares from a private balance to a public balance
    /// @dev User must provide a private authwit on the shares token authorizing this vault to burn shares
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn redeem_private_to_public(from: AztecAddress, to: AztecAddress, shares: u128, nonce: Field) {
        let shares_token = self.storage.shares.read();
        _validate_from_private::<4>(self.context, from);

        // Burn shares from the sender's private balance on the shares token
        self.call(Token::at(shares_token).burn_private(from, shares, nonce));

        // Burn shares and redeem public assets
        self.enqueue_self.settle_redeem_private_to_public_internal(to, shares);
    }

    /// @notice Redeems an amount of the shares from a private balance to a private balance
    /// @dev min_assets is the amount of assets that will be transferred to the recipient immediately in private.
    ///      Any outstanding assets the recipient is entitled to, will be sent through a commitment once the call is executed publicly.
    ///      User must provide a private authwit on the shares token authorizing this vault to burn shares.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to burn
    /// @param min_assets The minimum amount of assets to withdraw, immediately in private
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn redeem_private_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        min_assets: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        _validate_from_private::<5>(self.context, from);

        // Initialize commitment on the asset token that allows to transfer outstanding assets to the recipient in public
        let asset_commitment = self.call(Token::at(asset_token)
            .initialize_transfer_commitment(to, self.address));

        // Burn shares from the sender's private balance on the shares token
        self.call(Token::at(shares_token).burn_private(from, shares, nonce));

        // Order matters: transfer after burning to neutralize ARC-403 reentrancy via the `tokens_received` hook.
        // Transfers any outstanding assets without revealing the recipient
        // Reverts if min_assets is greater than allowed
        self.enqueue_self.settle_redeem_private_to_private_exact_internal(
            asset_commitment,
            shares,
            min_assets,
        );

        // Transfer min_assets to the recipient
        self.call(Token::at(asset_token).transfer_public_to_private(
            self.address,
            to,
            min_assets,
            0,
        ));
    }

    /// @notice Redeems an amount of the shares from a public balance to a private balance
    /// @dev min_assets is the amount of assets that will be transferred to the recipient immediately in private.
    ///      Any outstanding assets the recipient is entitled to, will be sent through a commitment once the call is executed publicly.
    ///      User must provide a public authwit on the shares token authorizing this vault to burn shares.
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param shares The amount of shares to redeem
    /// @param min_assets The minimum amount of assets to withdraw, immediately in private
    /// @param nonce The nonce used for authwitness
    #[external("private")]
    fn redeem_public_to_private_exact(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        min_assets: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        _validate_from_private::<5>(self.context, from);

        // Initialize commitment on the asset token that allows to transfer outstanding assets to the recipient in public
        let asset_commitment = self.call(Token::at(asset_token)
            .initialize_transfer_commitment(to, self.address));

        // Order matters: transfer after burning to neutralize ARC-403 reentrancy via the `tokens_received` hook.
        // Burns shares and transfers any outstanding assets without revealing the recipient
        // Reverts if min_assets is greater than allowed
        self.enqueue_self.settle_redeem_public_to_private_exact_internal(
            from,
            asset_commitment,
            shares,
            min_assets,
            nonce,
        );

        // Transfer min_assets to the recipient
        self.call(Token::at(asset_token).transfer_public_to_private(
            self.address,
            to,
            min_assets,
            0,
        ));
    }

    /** ==========================================================
     * ======================= VAULT VIEW ========================
     * ======================================================== */

    /// @notice Returns the admin address
    /// @return The address of the admin
    #[external("public")]
    #[view]
    fn admin() -> AztecAddress {
        self.storage.admin.read()
    }

    /// @notice Returns the underlying asset address
    /// @return The address of the underlying asset
    #[external("public")]
    #[view]
    fn asset() -> AztecAddress {
        self.storage.asset.read()
    }

    /// @notice Returns the shares token address
    /// @return The address of the shares token
    #[external("public")]
    #[view]
    fn shares() -> AztecAddress {
        self.storage.shares.read()
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
        _convert_to_shares(
            assets,
            self.internal._total_assets(),
            self.internal._total_supply_of_shares(),
            self.storage.vault_offset.read(),
            ROUND_DOWN,
        )
    }

    /// @notice Converts an amount of shares to assets using the current exchange rate
    /// @param shares The amount of shares to convert
    /// @return The equivalent amount of assets
    #[external("public")]
    #[view]
    fn convert_to_assets(shares: u128) -> u128 {
        _convert_to_assets(
            shares,
            self.internal._total_assets(),
            self.internal._total_supply_of_shares(),
            self.storage.vault_offset.read(),
            ROUND_DOWN,
        )
    }

    /// @dev Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver, through a deposit call.
    /// @param _receiver The address of the receiver
    /// @return The maximum amount of assets that can be deposited
    #[external("public")]
    #[view]
    fn max_deposit(_receiver: AztecAddress) -> u128 {
        MAX_U128_VALUE
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given current on-chain conditions.
    /// @param assets The amount of assets to deposit
    /// @return The amount of shares that would be minted
    #[external("public")]
    #[view]
    fn preview_deposit(assets: u128) -> u128 {
        _convert_to_shares(
            assets,
            self.internal._total_assets(),
            self.internal._total_supply_of_shares(),
            self.storage.vault_offset.read(),
            ROUND_DOWN,
        )
    }

    /// @dev Returns the maximum amount of the Vault shares that can be issued for the receiver, through a mint call.
    /// @param _receiver The address of the receiver
    /// @return The maximum amount of shares that can be issued
    #[external("public")]
    #[view]
    fn max_issue(_receiver: AztecAddress) -> u128 {
        MAX_U128_VALUE
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their issue at the current block, given current on-chain conditions.
    /// @param shares The amount of shares to issue
    /// @return The amount of assets required to issue the shares
    #[external("public")]
    #[view]
    fn preview_issue(shares: u128) -> u128 {
        _convert_to_assets(
            shares,
            self.internal._total_assets(),
            self.internal._total_supply_of_shares(),
            self.storage.vault_offset.read(),
            ROUND_UP,
        )
    }

    /// @dev Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the Vault, through a withdraw call.
    /// @notice This does NOT include private balance - private holders must track their own balance.
    /// @param owner The address of the owner
    /// @return The maximum amount of assets that can be withdrawn
    #[external("public")]
    #[view]
    fn max_withdraw(owner: AztecAddress) -> u128 {
        let shares_token = self.storage.shares.read();
        let owner_shares =
            self.view(Token::at(shares_token).balance_of_public(owner));
        let total_assets = self.internal._total_assets();
        let total_supply = self.internal._total_supply_of_shares();
        let vault_offset = self.storage.vault_offset.read();
        _convert_to_assets(
            owner_shares,
            total_assets,
            total_supply,
            vault_offset,
            ROUND_DOWN,
        )
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their withdraw at the current block, given current on-chain conditions.
    /// @param assets The amount of assets to withdraw
    /// @return The amount of shares that would be withdrawn
    #[external("public")]
    #[view]
    fn preview_withdraw(assets: u128) -> u128 {
        _convert_to_shares(
            assets,
            self.internal._total_assets(),
            self.internal._total_supply_of_shares(),
            self.storage.vault_offset.read(),
            ROUND_UP,
        )
    }

    /// @dev Returns the maximum amount of the Vault shares that can be redeemed from the owner balance in the Vault, through a redeem call.
    /// @notice This does NOT include private balance - private holders must track their own balance.
    /// @param owner The address of the owner
    /// @return The maximum amount of shares that can be redeemed
    #[external("public")]
    #[view]
    fn max_redeem(owner: AztecAddress) -> u128 {
        let shares_token = self.storage.shares.read();
        self.view(Token::at(shares_token).balance_of_public(owner))
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their redeem at the current block, given current on-chain conditions.
    /// @param shares The amount of shares to redeem
    /// @return The amount of assets that would be redeemed
    #[external("public")]
    #[view]
    fn preview_redeem(shares: u128) -> u128 {
        _convert_to_assets(
            shares,
            self.internal._total_assets(),
            self.internal._total_supply_of_shares(),
            self.storage.vault_offset.read(),
            ROUND_DOWN,
        )
    }

    /// @notice Returns the vault offset
    /// @return The offset value
    #[external("public")]
    #[view]
    fn get_vault_offset() -> u128 {
        self.storage.vault_offset.read()
    }

    /** ==========================================================
     * ==================== VAULT INTERNALS ======================
     * ======================================================== */

    // Settlement functions adjust for pre-applied state changes.
    // In the separated model, private cross-contract calls (e.g. shares.mint_to_private, shares.burn_private)
    // enqueue public state changes that execute BEFORE the vault's settlement functions.
    // Settlement must reconstruct the pre-operation state by adding/subtracting the known amounts.

    /// @notice Burns shares held in public for a given amount of assets
    /// @param from The address of the sender
    /// @param assets The amount of assets to burn shares for
    /// @param nonce The nonce used for authwitness on the shares token
    #[external("public")]
    #[only_self]
    fn settle_withdraw_public_to_private_internal(from: AztecAddress, assets: u128, nonce: Field) {
        let shares_token = self.storage.shares.read();
        // No pre-applied state changes to shares (public burn happens here)
        // Asset balance NOT yet decreased (transfer_public_to_private enqueue runs after this)
        let total_assets = self.internal._total_assets();
        let total_supply = self.internal._total_supply_of_shares();
        let vault_offset = self.storage.vault_offset.read();
        let shares = _convert_to_shares(assets, total_assets, total_supply, vault_offset, ROUND_UP);

        // Burn shares from user's public balance on shares token (requires authwit)
        self.call(Token::at(shares_token).burn_public(from, shares, nonce));
    }

    /// @notice Validates that the requested shares amount is valid for the given assets
    /// @param assets The amount of assets being withdrawn
    /// @param shares The amount of shares being burned
    #[external("public")]
    #[only_self]
    fn settle_withdraw_private_to_private_internal(assets: u128, shares: u128) {
        // Pre-applied: shares.decrease_total_supply(shares)
        // Asset balance NOT yet decreased (transfer_public_to_private enqueue runs after this)
        let total_assets = self.internal._total_assets();
        let total_supply_post = self.internal._total_supply_of_shares();
        let total_supply = total_supply_post + shares;
        let vault_offset = self.storage.vault_offset.read();
        let min_shares =
            _convert_to_shares(assets, total_assets, total_supply, vault_offset, ROUND_UP);

        assert(min_shares <= shares, "Insufficient shares burnt");
    }

    /// @notice Withdraws assets to a public balance for a given amount of shares
    /// @param to The address of the recipient
    /// @param shares The amount of shares being redeemed
    #[external("public")]
    #[only_self]
    fn settle_redeem_private_to_public_internal(to: AztecAddress, shares: u128) {
        let asset_token = self.storage.asset.read();
        // Pre-applied: shares.decrease_total_supply(shares) from burn_private
        let total_supply_post = self.internal._total_supply_of_shares();
        let total_supply = total_supply_post + shares;
        let total_assets = self.internal._total_assets();
        let vault_offset = self.storage.vault_offset.read();
        let assets =
            _convert_to_assets(shares, total_assets, total_supply, vault_offset, ROUND_DOWN);

        // Transfer the assets to the recipient
        self.call(Token::at(asset_token).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Mints shares to a public balance for a given amount of assets
    /// @param to The address of the recipient
    /// @param assets The amount of assets being deposited
    #[external("public")]
    #[only_self]
    fn settle_deposit_private_to_public_internal(to: AztecAddress, assets: u128) {
        let shares_token = self.storage.shares.read();
        // Pre-applied: asset.increase_public_balance(self, assets) from transfer_private_to_public
        // No pre-applied changes to shares total_supply (public mint happens here)
        let total_assets_post = self.internal._total_assets();
        let total_assets = total_assets_post - assets;
        let total_supply = self.internal._total_supply_of_shares();
        let vault_offset = self.storage.vault_offset.read();
        let shares =
            _convert_to_shares(assets, total_assets, total_supply, vault_offset, ROUND_DOWN);

        // Mint shares to the recipient on the shares token
        self.call(Token::at(shares_token).mint_to_public(to, shares));
    }

    /// @notice Validates that the requested shares amount is valid for the deposited assets
    /// @param from The address of the sender
    /// @param assets The amount of assets being deposited
    /// @param shares The amount of shares being issued
    /// @param nonce The nonce used for authwitness
    #[external("public")]
    #[only_self]
    fn settle_deposit_public_to_private_internal(
        from: AztecAddress,
        assets: u128,
        shares: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        // No pre-applied state changes: shares.increase_total_supply(shares) enqueues after this
        let total_supply = self.internal._total_supply_of_shares();
        let total_assets = self.internal._total_assets(); // Assets not transferred yet
        let vault_offset = self.storage.vault_offset.read();
        let max_shares =
            _convert_to_shares(assets, total_assets, total_supply, vault_offset, ROUND_DOWN);

        assert(shares <= max_shares, "Too many shares requested");

        // Order matters: transfer before minting to neutralize ARC-403 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(asset_token).transfer_public_to_public(
            from,
            self.address,
            assets,
            nonce,
        ));
    }

    /// @notice Validates that the requested shares amount is valid for the deposited assets
    /// @param assets The amount of assets being deposited
    /// @param shares The amount of shares being issued
    #[external("public")]
    #[only_self]
    fn settle_deposit_private_to_private_internal(assets: u128, shares: u128) {
        // Pre-applied: asset.increase_public_balance(self, assets), shares.increase_total_supply(shares)
        let total_assets_post = self.internal._total_assets();
        let total_supply_post = self.internal._total_supply_of_shares();
        let total_assets = total_assets_post - assets;
        let total_supply = total_supply_post - shares;
        let vault_offset = self.storage.vault_offset.read();
        let max_shares =
            _convert_to_shares(assets, total_assets, total_supply, vault_offset, ROUND_DOWN);

        assert(shares <= max_shares, "Too many shares requested");
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
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        // Pre-applied: shares.decrease_total_supply(max_shares) from burn_private
        let total_supply_post = self.internal._total_supply_of_shares();
        let total_supply = total_supply_post + max_shares;
        let total_assets = self.internal._total_assets(); // Assets not transferred yet
        let vault_offset = self.storage.vault_offset.read();
        let shares = _convert_to_shares(assets, total_assets, total_supply, vault_offset, ROUND_UP);

        let surplus = max_shares - shares; // Reverts with underflow if invalid
        if surplus > 0 {
            // Mint surplus back to the sender via commitment on shares token
            self.call(Token::at(shares_token).mint_to_commitment(commitment, surplus));
        }

        // Transfer the assets to the recipient
        self.call(Token::at(asset_token).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));
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
        let shares_token = self.storage.shares.read();
        // Pre-applied: shares.decrease_total_supply(max_shares)
        // Asset balance NOT yet decreased (transfer_public_to_private enqueue runs after this)
        let total_supply_post = self.internal._total_supply_of_shares();
        let total_assets = self.internal._total_assets();
        let total_supply = total_supply_post + max_shares;
        let vault_offset = self.storage.vault_offset.read();
        let shares = _convert_to_shares(assets, total_assets, total_supply, vault_offset, ROUND_UP);

        let surplus = max_shares - shares; // Reverts with underflow if invalid
        if surplus > 0 {
            // Mint surplus back to the sender via commitment on shares token
            self.call(Token::at(shares_token).mint_to_commitment(commitment, surplus));
        }
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
        let shares_token = self.storage.shares.read();
        // Pre-applied: asset.increase_public_balance(self, assets), shares.increase_total_supply(min_shares)
        let total_assets_post = self.internal._total_assets();
        let total_supply_post = self.internal._total_supply_of_shares();
        let total_assets = total_assets_post - assets;
        let total_supply = total_supply_post - min_shares;
        let vault_offset = self.storage.vault_offset.read();
        let max_shares =
            _convert_to_shares(assets, total_assets, total_supply, vault_offset, ROUND_DOWN);

        let outstanding_shares = max_shares - min_shares; // Reverts with underflow if invalid
        if outstanding_shares > 0 {
            // Mint outstanding shares via commitment on shares token
            self.call(Token::at(shares_token).mint_to_commitment(
                commitment,
                outstanding_shares,
            ));
        }
    }

    /// @notice Increases shares total supply and issues outstanding shares via commitment
    /// @param from The address of the sender
    /// @param commitment The partial note representing the commitment (privacy entrance)
    /// @param assets The amount of assets being deposited
    /// @param min_shares The minimum amount of shares that should be issued
    /// @param nonce The nonce used for authwitness
    #[external("public")]
    #[only_self]
    fn settle_deposit_public_to_private_exact_internal(
        from: AztecAddress,
        commitment: Field,
        assets: u128,
        min_shares: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        // No pre-applied state changes: shares.increase_total_supply(min_shares) enqueues after this
        // Assets not transferred yet
        let total_supply = self.internal._total_supply_of_shares();
        let total_assets = self.internal._total_assets();
        let vault_offset = self.storage.vault_offset.read();
        let max_shares =
            _convert_to_shares(assets, total_assets, total_supply, vault_offset, ROUND_DOWN);
        let outstanding_shares = max_shares - min_shares; // Reverts with underflow if invalid

        // Order matters: transfer before minting to neutralize ARC-403 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(asset_token).transfer_public_to_public(
            from,
            self.address,
            assets,
            nonce,
        ));

        if outstanding_shares > 0 {
            // Mint outstanding shares via commitment on shares token
            self.call(Token::at(shares_token).mint_to_commitment(
                commitment,
                outstanding_shares,
            ));
        }
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
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        // Pre-applied: asset.increase_public_balance(self, max_assets) from transfer_private_to_public
        // No pre-applied changes to shares total_supply (public mint happens here)
        let total_assets_post = self.internal._total_assets();
        let total_assets = total_assets_post - max_assets;
        let total_supply = self.internal._total_supply_of_shares();
        let vault_offset = self.storage.vault_offset.read();
        let assets = _convert_to_assets(shares, total_assets, total_supply, vault_offset, ROUND_UP);

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            self.call(Token::at(asset_token).transfer_public_to_commitment(
                self.address,
                asset_commitment,
                change,
                0,
            ));
        }

        // Mint shares to the recipient on the shares token (after refund to prevent inflated total_assets via ARC-403 reentrancy)
        self.call(Token::at(shares_token).mint_to_public(to, shares));
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
        let asset_token = self.storage.asset.read();
        // Pre-applied: asset.increase_public_balance(self, max_assets), shares.increase_total_supply(shares)
        let total_assets_post = self.internal._total_assets();
        let total_supply_post = self.internal._total_supply_of_shares();
        let total_assets = total_assets_post - max_assets;
        let total_supply = total_supply_post - shares;
        let vault_offset = self.storage.vault_offset.read();
        let assets = _convert_to_assets(shares, total_assets, total_supply, vault_offset, ROUND_UP);

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            self.call(Token::at(asset_token).transfer_public_to_commitment(
                self.address,
                asset_commitment,
                change,
                0,
            ));
        }
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
        let asset_token = self.storage.asset.read();
        // Pre-applied: shares.decrease_total_supply(shares)
        // Asset balance NOT yet decreased (transfer_public_to_private enqueue runs after this)
        let total_supply_post = self.internal._total_supply_of_shares();
        let total_assets = self.internal._total_assets();
        let total_supply = total_supply_post + shares;
        let vault_offset = self.storage.vault_offset.read();
        let assets =
            _convert_to_assets(shares, total_assets, total_supply, vault_offset, ROUND_DOWN);

        let outstanding_assets = assets - min_assets; // Reverts with underflow if invalid
        if outstanding_assets > 0 {
            self.call(Token::at(asset_token).transfer_public_to_commitment(
                self.address,
                asset_commitment,
                outstanding_assets,
                0,
            ));
        }
    }

    /// @notice Validates share redemption rate and withdraws any outstanding assets via commitment
    /// @param from The address of the sender
    /// @param asset_commitment The partial note representing the commitment (privacy entrance)
    /// @param shares The amount of shares being redeemed
    /// @param min_assets The minimum amount of assets that should be withdrawn
    /// @param nonce The nonce used for authwitness on the shares token
    #[external("public")]
    #[only_self]
    fn settle_redeem_public_to_private_exact_internal(
        from: AztecAddress,
        asset_commitment: Field,
        shares: u128,
        min_assets: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        let shares_token = self.storage.shares.read();
        // No pre-applied changes to shares total_supply (public burn happens here)
        // Asset balance NOT yet decreased (transfer_public_to_private enqueue runs after this)
        let total_assets = self.internal._total_assets();
        let total_supply = self.internal._total_supply_of_shares();
        let vault_offset = self.storage.vault_offset.read();
        let assets =
            _convert_to_assets(shares, total_assets, total_supply, vault_offset, ROUND_DOWN);

        // Burn the sender's shares on the shares token (requires authwit)
        self.call(Token::at(shares_token).burn_public(from, shares, nonce));

        let outstanding_assets = assets - min_assets; // Reverts with underflow if invalid
        if outstanding_assets > 0 {
            self.call(Token::at(asset_token).transfer_public_to_commitment(
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
    /// @param nonce The nonce used for authwitness
    #[external("public")]
    #[only_self]
    fn settle_issue_public_to_private_internal(
        from: AztecAddress,
        shares: u128,
        max_assets: u128,
        nonce: Field,
    ) {
        let asset_token = self.storage.asset.read();
        // No pre-applied state changes: shares.increase_total_supply(shares) enqueues after this
        // Assets not transferred yet
        let total_supply = self.internal._total_supply_of_shares();
        let total_assets = self.internal._total_assets();
        let vault_offset = self.storage.vault_offset.read();
        let assets = _convert_to_assets(shares, total_assets, total_supply, vault_offset, ROUND_UP);

        // Order matters: transfer before minting to neutralize ARC-403 reentrancy via the `tokens_to_send` hook.
        // Take the assets from the sender
        self.call(Token::at(asset_token).transfer_public_to_public(
            from,
            self.address,
            max_assets,
            nonce,
        ));

        let change = max_assets - assets; // Reverts with underflow if invalid
        if change > 0 {
            self.call(Token::at(asset_token).transfer_public_to_public(
                self.address,
                from,
                change,
                0,
            ));
        }
    }

    /** ==========================================================
     * ================== VAULT LIBRARIES ========================
     * ======================================================== */

    /// @notice Returns the total amount of underlying assets held by the vault
    /// @return The total amount of assets held by the vault
    #[internal("public")]
    fn _total_assets() -> u128 {
        let asset_token = self.storage.asset.read();
        self.view(Token::at(asset_token).balance_of_public(self.address))
    }

    /// @notice Returns the total supply of shares
    /// @return The total supply of shares
    #[internal("public")]
    fn _total_supply_of_shares() -> u128 {
        let shares_token = self.storage.shares.read();
        self.view(Token::at(shares_token).total_supply())
    }

    /// @notice Converts an amount of assets to shares using the given exchange rate parameters
    /// @param assets The amount of assets to convert
    /// @param total_assets The total amount of assets in the vault
    /// @param total_supply The total supply of shares
    /// @param vault_offset The vault offset
    /// @param rounding The rounding direction (ROUND_UP or ROUND_DOWN)
    /// @return The equivalent amount of shares
    #[contract_library_method]
    fn _convert_to_shares(
        assets: u128,
        total_assets: u128,
        total_supply: u128,
        vault_offset: u128,
        rounding: bool,
    ) -> u128 {
        let mul_term = assets * (total_supply + vault_offset);
        let denominator = total_assets + 1;
        let mut shares = mul_term / denominator;
        if (rounding == ROUND_UP) & (mul_term % denominator > 0) {
            shares = shares + 1;
        }
        shares
    }

    /// @notice Converts an amount of shares to assets using the given exchange rate parameters
    /// @param shares The amount of shares to convert
    /// @param total_assets The total amount of assets in the vault
    /// @param total_supply The total supply of shares
    /// @param vault_offset The vault offset
    /// @param rounding The rounding direction (ROUND_UP or ROUND_DOWN)
    /// @return The equivalent amount of assets
    #[contract_library_method]
    fn _convert_to_assets(
        shares: u128,
        total_assets: u128,
        total_supply: u128,
        vault_offset: u128,
        rounding: bool,
    ) -> u128 {
        let mul_term = shares * (total_assets + 1);
        let denominator = total_supply + vault_offset;
        let mut assets = mul_term / denominator;
        if (rounding == ROUND_UP) & (mul_term % denominator > 0) {
            assets = assets + 1;
        }
        assets
    }

    /** ==========================================================
     * =================== UPGRADEABLE ==========================
     * ======================================================== */

    /// @notice Upgrades the contract to a new contract class id
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
     * ================= AUTH LIBRARIES =========================
     * ======================================================== */

    /// @notice Validates that the caller possesses authwit from the `from` address or the caller is the `from` address
    #[contract_library_method]
    fn _validate_from_private<let N: u32>(context: &mut PrivateContext, from: AztecAddress) {
        if (!from.eq(context.maybe_msg_sender().unwrap())) {
            assert_current_call_valid_authwit::<N>(context, from);
        }
    }

    /// @notice Validates that the caller possesses authwit from the `from` address or the caller is the `from` address
    #[internal("public")]
    fn _validate_from_public(from: AztecAddress) {
        if (!from.eq(self.msg_sender())) {
            assert_current_call_valid_authwit_public(self.context, from);
        }
    }
}
