use crate::Vault;
use aztec::{
    oracle::random::random,
    protocol::{address::AztecAddress, contract_class_id::ContractClassId},
    test::helpers::{test_environment::{DeployOptions, TestEnvironment}, txe_oracles as cheatcodes},
};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use token_contract::Token;

pub global mint_amount: u128 = 10_000 as u128;

pub unconstrained fn get_token_class_id() -> ContractClassId {
    let token_instance = cheatcodes::deploy(
        "@token_contract/Token",
        "",
        [],
        random(),
        random(),
        AztecAddress::zero(),
    );
    token_instance.contract_class_id
}

/// @notice Sets up a vault with an asset token and a shares token.
/// Deploys 3 contracts: asset token (with owner as minter), vault, and shares token (with vault
/// as minter). The vault constructor computes the shares token address deterministically using
/// salt, deployer, class_id, and initialization parameters. The shares token is deployed with a
/// known salt (shares_salt) so that the vault's computed address matches the actual shares
/// deployment.
///
/// Since the regular constructor only computes and stores the shares address (without interacting
/// with the shares contract), the vault can be deployed and initialized before shares exists.
///
/// The shares_class_id is obtained dynamically via a throwaway deploy of the token contract.
pub unconstrained fn setup_with_vault(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let (owner, recipient) = if with_account_contracts {
        let owner = env.create_contract_account();
        let recipient = env.create_contract_account();
        (owner, recipient)
    } else {
        let owner = env.create_light_account();
        let recipient = env.create_light_account();
        (owner, recipient)
    };

    let shares_class_id = get_token_class_id();
    let shares_salt: Field = random();

    // Deploy asset token with owner as minter
    let asset_initializer = Token::interface().constructor_with_minter(
        "AssetToken000000000000000000000",
        "ASSET00000000000000000000000000",
        6,
        owner,
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    // Deploy and initialize vault - the constructor computes the shares address deterministically
    // without interacting with the shares contract, so shares doesn't need to exist yet
    let vault_initializer = Vault::interface().constructor(
        asset_address,
        1,
        "SharesToken00000000000000000000",
        "SHARES0000000000000000000000000",
        18,
        shares_class_id,
        shares_salt,
    );
    let vault_address =
        env.deploy("@vault_contract/Vault").with_public_initializer(owner, vault_initializer);

    // Deploy shares token at the address the vault computed, using the matching shares_salt.
    // secret=0 gives PublicKeys::default(), matching the vault's _compute_token_address.
    let shares_initializer = Token::interface().constructor_with_minter(
        "SharesToken00000000000000000000",
        "SHARES0000000000000000000000000",
        18,
        vault_address,
    );
    let shares_address = env
        .deploy_opts(
            DeployOptions::new().with_salt(shares_salt).with_secret(0),
            "@token_contract/Token",
        )
        .with_public_initializer(owner, shares_initializer);

    (env, vault_address, owner, recipient, asset_address, shares_address)
}

/// @notice Sets up a vault with an initial deposit for inflation-attack protection.
/// Uses constructor_with_initial_deposit which transfers assets from the depositor and mints
/// permanently-locked shares to the vault during initialization.
///
/// Because the initializer mints shares to the vault, the shares token must exist before the
/// initializer runs. We deploy the vault instance with the real constructor data (so the address
/// includes the correct initialization_hash) but defer the initializer call until after shares
/// is deployed. This mirrors the TS test flow where the vault address is precomputed, shares is
/// deployed first, then the vault is deployed with its constructor.
pub unconstrained fn setup_with_vault_initial_deposit(
    with_account_contracts: bool,
    initial_deposit: u128,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let (owner, recipient) = if with_account_contracts {
        let owner = env.create_contract_account();
        let recipient = env.create_contract_account();
        (owner, recipient)
    } else {
        let owner = env.create_light_account();
        let recipient = env.create_light_account();
        (owner, recipient)
    };

    let shares_class_id = get_token_class_id();
    let shares_salt: Field = random();

    // Deploy asset token with owner as minter
    let asset_initializer = Token::interface().constructor_with_minter(
        "AssetToken000000000000000000000",
        "ASSET00000000000000000000000000",
        6,
        owner,
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    // Mint initial_deposit of assets to owner before vault deployment
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, initial_deposit));

    // Deploy vault instance with the actual constructor_with_initial_deposit data so the
    // initialization_hash (and therefore the vault address) is correct. The initializer is
    // deferred until after shares is deployed since it mints shares to the vault.
    let vault_init = Vault::interface().constructor_with_initial_deposit(
        asset_address,
        1,
        "SharesToken00000000000000000000",
        "SHARES0000000000000000000000000",
        18,
        shares_class_id,
        shares_salt,
        initial_deposit,
        owner,
        0,
    );
    let vault_instance = cheatcodes::deploy(
        "@vault_contract/Vault",
        vault_init.name,
        vault_init.args,
        random(),
        random(),
        AztecAddress::zero(),
    );
    let vault_address = vault_instance.to_address();

    // Deploy shares token with vault as minter, using the matching shares_salt.
    // secret=0 gives PublicKeys::default(), matching the vault's _compute_token_address.
    let shares_initializer = Token::interface().constructor_with_minter(
        "SharesToken00000000000000000000",
        "SHARES0000000000000000000000000",
        18,
        vault_address,
    );
    let shares_address = env
        .deploy_opts(
            DeployOptions::new().with_salt(shares_salt).with_secret(0),
            "@token_contract/Token",
        )
        .with_public_initializer(owner, shares_initializer);

    // Authorize vault to transfer assets from owner during initialization
    authorize_transfer_public_to_public(env, asset_address, vault_address, owner, initial_deposit);

    // Now call the vault initializer - shares exists so the constructor can mint shares
    env.call_public(
        owner,
        Vault::at(vault_address).constructor_with_initial_deposit(
            asset_address,
            1,
            "SharesToken00000000000000000000",
            "SHARES0000000000000000000000000",
            18,
            shares_class_id,
            shares_salt,
            initial_deposit,
            owner,
            0,
        ),
    );

    (env, vault_address, owner, recipient, asset_address, shares_address)
}

/// @notice Deploys a vault without calling any initializer (for failure tests).
/// All PublicImmutable fields remain uninitialized, so any operation that reads storage will revert.
pub unconstrained fn setup_vault_without_shares() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();
    let recipient = env.create_light_account();

    // Deploy asset token with owner as minter
    let asset_initializer = Token::interface().constructor_with_minter(
        "AssetToken000000000000000000000",
        "ASSET00000000000000000000000000",
        6,
        owner,
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    // Deploy vault without initializer - all storage remains uninitialized
    let vault_address = env.deploy("@vault_contract/Vault").without_initializer();

    (env, vault_address, owner, recipient, asset_address)
}

// ====================== Balance helpers ======================

pub unconstrained fn check_public_balance(
    env: TestEnvironment,
    token_address: AztecAddress,
    address: AztecAddress,
    expected_amount: u128,
) {
    let amount = get_public_balance(env, token_address, address);
    assert(amount == expected_amount, "Public balance is not correct");
}

pub unconstrained fn get_public_balance(
    env: TestEnvironment,
    token_address: AztecAddress,
    address: AztecAddress,
) -> u128 {
    env.view_public(Token::at(token_address).balance_of_public(address))
}

pub unconstrained fn check_private_balance(
    env: TestEnvironment,
    token_address: AztecAddress,
    address: AztecAddress,
    expected_amount: u128,
) {
    let balance = get_private_balance(env, token_address, address);
    assert(balance == expected_amount, "Private balance is not correct");
}

pub unconstrained fn get_private_balance(
    env: TestEnvironment,
    token_address: AztecAddress,
    address: AztecAddress,
) -> u128 {
    env.execute_utility(Token::at(token_address).balance_of_private(address))
}

// ====================== Authwit helpers ======================

pub unconstrained fn authorize_transfer_public_to_public(
    env: TestEnvironment,
    token: AztecAddress,
    caller: AztecAddress,
    from: AztecAddress,
    amount: u128,
) {
    let call_interface = Token::at(token).transfer_public_to_public(from, caller, amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call(env, from, caller, call_interface);
}

pub unconstrained fn authorize_transfer_private_to_public(
    env: TestEnvironment,
    token: AztecAddress,
    caller: AztecAddress,
    from: AztecAddress,
    amount: u128,
) {
    let call_interface = Token::at(token).transfer_private_to_public(from, caller, amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call(env, from, caller, call_interface);
}

/// @notice Authorizes the vault to burn shares from a user's public balance on the shares token
pub unconstrained fn authorize_burn_public(
    env: TestEnvironment,
    shares_token: AztecAddress,
    vault: AztecAddress,
    from: AztecAddress,
    amount: u128,
) {
    let call_interface = Token::at(shares_token).burn_public(from, amount, 0);
    authwit_cheatcodes::add_public_authwit_from_call(env, from, vault, call_interface);
}

/// @notice Authorizes the vault to burn shares from a user's private balance on the shares token
pub unconstrained fn authorize_burn_private(
    env: TestEnvironment,
    shares_token: AztecAddress,
    vault: AztecAddress,
    from: AztecAddress,
    amount: u128,
) {
    let call_interface = Token::at(shares_token).burn_private(from, amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call(env, from, vault, call_interface);
}

// ====================== Redeem helpers ======================

pub unconstrained fn redeem_public_to_public(
    env: TestEnvironment,
    vault_address: AztecAddress,
    shares_address: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    shares: u128,
) {
    authorize_burn_public(env, shares_address, vault_address, from, shares);
    env.call_public(from, Vault::at(vault_address).redeem_public_to_public(from, to, shares, 0));
}

pub unconstrained fn redeem_public_to_private_exact(
    env: TestEnvironment,
    vault_address: AztecAddress,
    shares_address: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    shares: u128,
    min_assets: u128,
) {
    authorize_burn_public(env, shares_address, vault_address, from, shares);
    env.call_private(
        from,
        Vault::at(vault_address).redeem_public_to_private_exact(from, to, shares, min_assets, 0),
    );
}

pub unconstrained fn redeem_private_to_public(
    env: TestEnvironment,
    vault_address: AztecAddress,
    shares_address: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    shares: u128,
) {
    authorize_burn_private(env, shares_address, vault_address, from, shares);
    env.call_private(from, Vault::at(vault_address).redeem_private_to_public(from, to, shares, 0));
}

pub unconstrained fn redeem_private_to_private_exact(
    env: TestEnvironment,
    vault_address: AztecAddress,
    shares_address: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    shares: u128,
    min_assets: u128,
) {
    authorize_burn_private(env, shares_address, vault_address, from, shares);
    env.call_private(
        from,
        Vault::at(vault_address).redeem_private_to_private_exact(from, to, shares, min_assets, 0),
    );
}

// ====================== Withdraw helpers ======================

pub unconstrained fn withdraw_public_to_public(
    env: TestEnvironment,
    vault_address: AztecAddress,
    shares_address: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    assets: u128,
    shares_to_burn: u128,
) {
    authorize_burn_public(env, shares_address, vault_address, from, shares_to_burn);
    env.call_public(from, Vault::at(vault_address).withdraw_public_to_public(from, to, assets, 0));
}

pub unconstrained fn withdraw_public_to_private(
    env: TestEnvironment,
    vault_address: AztecAddress,
    shares_address: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    assets: u128,
    shares_to_burn: u128,
) {
    authorize_burn_public(env, shares_address, vault_address, from, shares_to_burn);
    env.call_private(from, Vault::at(vault_address).withdraw_public_to_private(from, to, assets, 0));
}

pub unconstrained fn withdraw_private_to_private(
    env: TestEnvironment,
    vault_address: AztecAddress,
    shares_address: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    assets: u128,
    shares_to_burn: u128,
) {
    authorize_burn_private(env, shares_address, vault_address, from, shares_to_burn);
    env.call_private(
        from,
        Vault::at(vault_address).withdraw_private_to_private(from, to, assets, shares_to_burn, 0),
    );
}

pub unconstrained fn withdraw_private_to_public_exact(
    env: TestEnvironment,
    vault_address: AztecAddress,
    shares_address: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    assets: u128,
    shares_to_burn: u128,
) {
    authorize_burn_private(env, shares_address, vault_address, from, shares_to_burn);
    env.call_private(
        from,
        Vault::at(vault_address).withdraw_private_to_public_exact(
            from,
            to,
            assets,
            shares_to_burn,
            0,
        ),
    );
}

pub unconstrained fn withdraw_private_to_private_exact(
    env: TestEnvironment,
    vault_address: AztecAddress,
    shares_address: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    assets: u128,
    shares_to_burn: u128,
) {
    authorize_burn_private(env, shares_address, vault_address, from, shares_to_burn);
    env.call_private(
        from,
        Vault::at(vault_address).withdraw_private_to_private_exact(
            from,
            to,
            assets,
            shares_to_burn,
            0,
        ),
    );
}

// ====================== Deposit helpers ======================

pub unconstrained fn mint_and_deposit_public_to_public(
    env: TestEnvironment,
    minter: AztecAddress,
    asset_address: AztecAddress,
    vault_address: AztecAddress,
    _shares_address: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
) {
    env.call_public(minter, Token::at(asset_address).mint_to_public(minter, amount));

    // Authorize the vault to use the caller's assets
    authorize_transfer_public_to_public(env, asset_address, vault_address, minter, amount);

    // Deposit
    env.call_public(
        minter,
        Vault::at(vault_address).deposit_public_to_public(minter, recipient, amount, 0),
    );
}

pub unconstrained fn mint_and_deposit_public_to_private(
    env: TestEnvironment,
    minter: AztecAddress,
    asset_address: AztecAddress,
    vault_address: AztecAddress,
    _shares_address: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
) {
    env.call_public(minter, Token::at(asset_address).mint_to_public(minter, amount));

    // Authorize the vault to use the caller's assets
    authorize_transfer_public_to_public(env, asset_address, vault_address, minter, amount);

    // Deposit
    env.call_private(
        minter,
        Vault::at(vault_address).deposit_public_to_private(minter, recipient, amount, amount, 0),
    );
}
