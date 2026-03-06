use crate::Vault;
use aztec::{
    hash::hash_args,
    protocol::{address::AztecAddress, traits::ToField},
    test::helpers::{test_environment::TestEnvironment, txe_oracles},
};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use token_contract::Token;

pub global mint_amount: u128 = 10_000 as u128;

/// @notice Sets up a vault with an asset token and a shares token.
/// Deploys 3 contracts: asset token (with owner as minter), vault (2-step init),
/// shares token (with vault as minter), then calls step1 + step2 + set_shares on the vault.
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

    // Deploy asset token with owner as minter
    let asset_initializer = Token::interface().constructor_with_minter(
        "AssetToken000000000000000000000",
        "ASSET00000000000000000000000000",
        6,
        owner,
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    let step1_args_hash = hash_args([asset_address.to_field(), 1 as Field]);

    // Register vault instance with constructor_step2's init_hash but do NOT execute step2 yet.
    // vault_address commits to hash(constructor_step2_selector, [step1_args_hash]).
    // Because constructor_step2 takes only step1_args_hash (not shares), there is no circular
    // dependency: vault_address does not depend on shares_address.
    let vault_deployment = env.deploy("@vault_contract/Vault");
    let vault_address = txe_oracles::deploy(
        "@vault_contract/Vault",
        "constructor_step2",
        [step1_args_hash],
        vault_deployment.secret,
    )
        .to_address();

    // Deploy shares token with the now-known vault_address as minter
    let shares_initializer = Token::interface().constructor_with_minter(
        "SharesToken00000000000000000000",
        "SHARES0000000000000000000000000",
        18,
        vault_address,
    );
    let shares_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, shares_initializer);

    // Tx 1: step 1 - emits step1_nullifier, sets asset and vault_offset (#[noinitcheck])
    env.call_public(owner, Vault::at(vault_address).constructor_step1(asset_address, 1));
    // Tx 2: step 2 - verifies step1_nullifier, marks vault as initialized (#[initializer])
    env.call_public(owner, Vault::at(vault_address).constructor_step2(step1_args_hash));
    // Tx 3: bind shares - verifies step1_nullifier, sets shares (regular public)
    env.call_public(
        owner,
        Vault::at(vault_address).constructor_step2_set_shares(step1_args_hash, shares_address),
    );

    (env, vault_address, owner, recipient, asset_address, shares_address)
}

/// @notice Sets up a vault with an initial deposit for inflation-attack protection
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

    // Deploy asset token with owner as minter
    let asset_initializer = Token::interface().constructor_with_minter(
        "AssetToken000000000000000000000",
        "ASSET00000000000000000000000000",
        6,
        owner,
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    let step1_args_hash = hash_args([asset_address.to_field(), 1 as Field]);

    // Register vault with constructor_step2's init_hash without executing step2
    let vault_deployment = env.deploy("@vault_contract/Vault");
    let vault_address = txe_oracles::deploy(
        "@vault_contract/Vault",
        "constructor_step2",
        [step1_args_hash],
        vault_deployment.secret,
    )
        .to_address();

    // Deploy shares token with vault_address as minter
    let shares_initializer = Token::interface().constructor_with_minter(
        "SharesToken00000000000000000000",
        "SHARES0000000000000000000000000",
        18,
        vault_address,
    );
    let shares_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, shares_initializer);

    // Mint initial_deposit of assets to owner
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, initial_deposit));

    // Authorize vault to transfer assets from owner
    authorize_transfer_public_to_public(env, asset_address, vault_address, owner, initial_deposit);

    // Tx 1: step 1
    env.call_public(owner, Vault::at(vault_address).constructor_step1(asset_address, 1));
    // Tx 2: step 2 (marks as initialized)
    env.call_public(owner, Vault::at(vault_address).constructor_step2(step1_args_hash));
    // Tx 3: bind shares + initial deposit
    env.call_public(
        owner,
        Vault::at(vault_address).constructor_step2_set_shares_with_initial_deposit(
            step1_args_hash,
            shares_address,
            initial_deposit,
            owner,
            0,
        ),
    );

    (env, vault_address, owner, recipient, asset_address, shares_address)
}

/// @notice Deploys a vault with step 1 and step 2 done but shares NOT set (for failure tests)
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

    let step1_args_hash = hash_args([asset_address.to_field(), 1 as Field]);

    // Register vault with step2's init_hash, call step1 + step2 but NOT set_shares
    let vault_deployment = env.deploy("@vault_contract/Vault");
    let vault_address = txe_oracles::deploy(
        "@vault_contract/Vault",
        "constructor_step2",
        [step1_args_hash],
        vault_deployment.secret,
    )
        .to_address();

    env.call_public(owner, Vault::at(vault_address).constructor_step1(asset_address, 1));
    env.call_public(owner, Vault::at(vault_address).constructor_step2(step1_args_hash));

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
    env.simulate_utility(Token::at(token_address).balance_of_private(address))
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
