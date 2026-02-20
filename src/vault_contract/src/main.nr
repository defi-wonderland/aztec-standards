pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract TokenizedVault {
    use aztec::{
        authwit::auth::{
            assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
        },
        context::PrivateContext,
        macros::{functions::{external, initializer, internal, only_self, view}, storage::storage},
        protocol::{
            address::AztecAddress,
            constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            contract_class_id::ContractClassId,
            traits::FromField,
        },
        state_vars::PublicImmutable,
    };
    use contract_instance_registry::ContractInstanceRegistry;
    use token_contract::Token;

    global ROUND_DOWN: bool = false;
    global ROUND_UP: bool = true;
    global MAX_U128_VALUE: u128 = 340282366920938463463374607431768211455;

    #[storage]
    struct Storage<Context> {
        asset: PublicImmutable<AztecAddress, Context>,
        vault_token: PublicImmutable<AztecAddress, Context>,
        vault_offset: PublicImmutable<u128, Context>,
        upgrade_authority: PublicImmutable<AztecAddress, Context>,
    }

    /// @notice Initializes the vault manager
    /// @param asset The underlying asset token address
    /// @param vault_token The share token address
    /// @param vault_offset The offset used to mitigate inflation attacks
    /// @param upgrade_authority The address with permission to upgrade this contract
    #[external("public")]
    #[initializer]
    fn constructor(
        asset: AztecAddress,
        vault_token: AztecAddress,
        vault_offset: u128,
        upgrade_authority: AztecAddress,
    ) {
        self.storage.asset.initialize(asset);
        self.storage.vault_token.initialize(vault_token);
        self.storage.vault_offset.initialize(vault_offset);
        self.storage.upgrade_authority.initialize(upgrade_authority);
    }

    /** ==========================================================
     * ======================= VAULT =============================
     * ======================================================== */

    /// @notice Deposits public assets and mints public shares
    #[external("public")]
    fn deposit_public_to_public(from: AztecAddress, to: AztecAddress, assets: u128, _nonce: Field) {
        self.internal._validate_from_public(from);

        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);

        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));
        self.internal._mint_shares_to_public(to, shares);
    }

    /// @notice Deposits private assets and mints public shares
    #[external("private")]
    fn deposit_private_to_public(from: AztecAddress, to: AztecAddress, assets: u128, _nonce: Field) {
        _validate_from_private::<4>(self.context, from);

        self.call(Token::at(self.storage.asset.read()).transfer_private_to_public(
            from,
            self.address,
            assets,
            _nonce,
        ));
        self.enqueue_self.settle_deposit_private_to_public_internal(to, assets);
    }

    /// @notice Issues exact public shares for public assets
    #[external("public")]
    fn issue_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        shares: u128,
        max_assets: u128,
        _nonce: Field,
    ) {
        self.internal._validate_from_public(from);

        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_UP);

        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            from,
            self.address,
            max_assets,
            _nonce,
        ));
        self.internal._mint_shares_to_public(to, shares);

        let change = max_assets - assets;
        if change > 0 {
            self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
                self.address,
                from,
                change,
                0,
            ));
        }
    }

    /// @notice Withdraws public assets by burning public shares
    #[external("public")]
    fn withdraw_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        assets: u128,
        _nonce: Field,
    ) {
        self.internal._validate_from_public(from);

        let total_assets = self.internal._total_assets();
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_UP);

        self.internal._burn_public_shares(from, shares, _nonce);
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /// @notice Redeems public shares for public assets
    #[external("public")]
    fn redeem_public_to_public(from: AztecAddress, to: AztecAddress, shares: u128, _nonce: Field) {
        self.internal._validate_from_public(from);

        let total_assets = self.internal._total_assets();
        let assets = self.internal._convert_to_assets(shares, total_assets, ROUND_DOWN);

        self.internal._burn_public_shares(from, shares, _nonce);
        self.call(Token::at(self.storage.asset.read()).transfer_public_to_public(
            self.address,
            to,
            assets,
            0,
        ));
    }

    /** ==========================================================
     * ===================== SETTLEMENT ==========================
     * ======================================================== */

    #[external("public")]
    #[only_self]
    fn settle_deposit_private_to_public_internal(to: AztecAddress, assets: u128) {
        let total_assets = self.internal._total_assets() - assets;
        let shares = self.internal._convert_to_shares(assets, total_assets, ROUND_DOWN);
        self.internal._mint_shares_to_public(to, shares);
    }

    /** ==========================================================
     * ====================== VAULT VIEW =========================
     * ======================================================== */

    #[external("public")]
    #[view]
    fn asset() -> AztecAddress {
        self.storage.asset.read()
    }

    #[external("public")]
    #[view]
    fn vault_token() -> AztecAddress {
        self.storage.vault_token.read()
    }

    #[external("public")]
    #[view]
    fn total_assets() -> u128 {
        self.internal._total_assets()
    }

    #[external("public")]
    #[view]
    fn total_supply() -> u128 {
        self.internal._share_total_supply()
    }

    #[external("public")]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> u128 {
        self.view(Token::at(self.storage.vault_token.read()).balance_of_public(owner))
    }

    #[external("public")]
    #[view]
    fn convert_to_shares(assets: u128) -> u128 {
        self.internal._convert_to_shares(assets, self.internal._total_assets(), ROUND_DOWN)
    }

    #[external("public")]
    #[view]
    fn convert_to_assets(shares: u128) -> u128 {
        self.internal._convert_to_assets(shares, self.internal._total_assets(), ROUND_DOWN)
    }

    #[external("public")]
    #[view]
    fn max_deposit(_receiver: AztecAddress) -> u128 {
        MAX_U128_VALUE
    }

    #[external("public")]
    #[view]
    fn preview_deposit(assets: u128) -> u128 {
        self.internal._convert_to_shares(assets, self.internal._total_assets(), ROUND_DOWN)
    }

    #[external("public")]
    #[view]
    fn max_issue(_receiver: AztecAddress) -> u128 {
        MAX_U128_VALUE
    }

    #[external("public")]
    #[view]
    fn preview_issue(shares: u128) -> u128 {
        self.internal._convert_to_assets(shares, self.internal._total_assets(), ROUND_UP)
    }

    #[external("public")]
    #[view]
    fn max_withdraw(owner: AztecAddress) -> u128 {
        let shares = self.view(Token::at(self.storage.vault_token.read()).balance_of_public(owner));
        self.internal._convert_to_assets(shares, self.internal._total_assets(), ROUND_DOWN)
    }

    #[external("public")]
    #[view]
    fn preview_withdraw(assets: u128) -> u128 {
        self.internal._convert_to_shares(assets, self.internal._total_assets(), ROUND_UP)
    }

    #[external("public")]
    #[view]
    fn max_redeem(owner: AztecAddress) -> u128 {
        self.view(Token::at(self.storage.vault_token.read()).balance_of_public(owner))
    }

    #[external("public")]
    #[view]
    fn preview_redeem(shares: u128) -> u128 {
        self.internal._convert_to_assets(shares, self.internal._total_assets(), ROUND_DOWN)
    }

    #[external("public")]
    #[view]
    fn get_vault_offset() -> u128 {
        self.storage.vault_offset.read()
    }

    /** ==========================================================
     * ======================== HELPERS ==========================
     * ======================================================== */

    #[internal("public")]
    fn _mint_shares_to_public(to: AztecAddress, amount: u128) {
        self.call(Token::at(self.storage.vault_token.read()).mint_to_public(to, amount));
    }

    #[internal("public")]
    fn _burn_public_shares(from: AztecAddress, amount: u128, nonce: Field) {
        self.call(Token::at(self.storage.vault_token.read()).burn_public(from, amount, nonce));
    }

    #[internal("public")]
    fn _total_assets() -> u128 {
        self.view(Token::at(self.storage.asset.read()).balance_of_public(self.address))
    }

    #[internal("public")]
    fn _share_total_supply() -> u128 {
        self.view(Token::at(self.storage.vault_token.read()).total_supply())
    }

    #[internal("public")]
    fn _convert_to_shares(assets: u128, total_assets: u128, rounding: bool) -> u128 {
        let mul_term = assets * (self.internal._share_total_supply() + self.storage.vault_offset.read());
        let denominator = total_assets + 1;
        let mut shares = mul_term / denominator;
        if (rounding == ROUND_UP) & (mul_term % denominator > 0) {
            shares = shares + 1;
        }
        shares
    }

    #[internal("public")]
    fn _convert_to_assets(shares: u128, total_assets: u128, rounding: bool) -> u128 {
        let mul_term = shares * (total_assets + 1);
        let denominator = self.internal._share_total_supply() + self.storage.vault_offset.read();
        let mut assets = mul_term / denominator;
        if (rounding == ROUND_UP) & (mul_term % denominator > 0) {
            assets = assets + 1;
        }
        assets
    }

    /** ==========================================================
     * ===================  UPGRADEABLE  =========================
     * ======================================================== */

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

    #[contract_library_method]
    fn _validate_from_private<let N: u32>(context: &mut PrivateContext, from: AztecAddress) {
        if (!from.eq(context.maybe_msg_sender().unwrap())) {
            assert_current_call_valid_authwit::<N>(context, from);
        }
    }

    #[internal("public")]
    fn _validate_from_public(from: AztecAddress) {
        if (!from.eq(self.msg_sender())) {
            assert_current_call_valid_authwit_public(self.context, from);
        }
    }
}
