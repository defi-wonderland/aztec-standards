use crate::Vault;
use aztec::{
    oracle::random::random,
    protocol::address::AztecAddress,
    test::helpers::{test_environment::TestEnvironment, txe_oracles as cheatcodes},
};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use token_contract::Token;

pub global mint_amount: u128 = 10_000 as u128;

// Vault IS the shares token - "shares_address" == vault_address in all helpers.

/// @notice Sets up a vault (which is itself the shares token) with an asset token.
/// Deploys 2 contracts: asset token (with owner as minter), vault (initializing token metadata).
/// Returns shares_address == vault_address since the vault IS the shares token.
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

    // Deploy vault with explicit deployer=owner; vault IS the shares token
    let vault_init = Vault::interface().constructor(
        asset_address,
        1,
        "SharesToken00000000000000000000",
        "SHARES0000000000000000000000000",
        18,
    );
    let vault_instance = cheatcodes::deploy(
        "@vault_contract/Vault",
        vault_init.name,
        vault_init.args,
        0,
        random(),
        owner,
    );
    let vault_address = vault_instance.to_address();
    env.call_public(
        owner,
        Vault::at(vault_address).constructor(
            asset_address,
            1,
            "SharesToken00000000000000000000",
            "SHARES0000000000000000000000000",
            18,
        ),
    );

    // vault_address == shares_address (vault IS the shares token)
    (env, vault_address, owner, recipient, asset_address, vault_address)
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

    // Mint initial_deposit of assets to owner before vault deployment
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, initial_deposit));

    // Deploy vault with explicit deployer=owner; initializer makes initial deposit
    let vault_init = Vault::interface().constructor_with_initial_deposit(
        asset_address,
        1,
        "SharesToken00000000000000000000",
        "SHARES0000000000000000000000000",
        18,
        initial_deposit,
        owner,
        0,
    );
    let vault_instance = cheatcodes::deploy(
        "@vault_contract/Vault",
        vault_init.name,
        vault_init.args,
        0,
        random(),
        owner,
    );
    let vault_address = vault_instance.to_address();

    // Authorize vault to transfer assets from owner for the initial deposit
    authorize_transfer_public_to_public(env, asset_address, vault_address, owner, initial_deposit);

    env.call_public(
        owner,
        Vault::at(vault_address).constructor_with_initial_deposit(
            asset_address,
            1,
            "SharesToken00000000000000000000",
            "SHARES0000000000000000000000000",
            18,
            initial_deposit,
            owner,
            0,
        ),
    );

    // vault_address == shares_address (vault IS the shares token)
    (env, vault_address, owner, recipient, asset_address, vault_address)
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

/// @notice No-op: vault IS the shares token and is its own authority - no authwit needed for burns
pub unconstrained fn authorize_burn_public(
    _env: TestEnvironment,
    _shares_token: AztecAddress,
    _vault: AztecAddress,
    _from: AztecAddress,
    _amount: u128,
) {}

/// @notice No-op: vault IS the shares token and is its own authority - no authwit needed for burns
pub unconstrained fn authorize_burn_private(
    _env: TestEnvironment,
    _shares_token: AztecAddress,
    _vault: AztecAddress,
    _from: AztecAddress,
    _amount: u128,
) {}

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
    env.call_public(from, Vault::at(vault_address).redeem_public_to_public(from, to, shares));
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
        Vault::at(vault_address).redeem_public_to_private_exact(from, to, shares, min_assets),
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
    env.call_private(from, Vault::at(vault_address).redeem_private_to_public(from, to, shares));
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
        Vault::at(vault_address).redeem_private_to_private_exact(from, to, shares, min_assets),
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
    env.call_public(from, Vault::at(vault_address).withdraw_public_to_public(from, to, assets));
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
    env.call_private(from, Vault::at(vault_address).withdraw_public_to_private(from, to, assets));
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
        Vault::at(vault_address).withdraw_private_to_private(from, to, assets, shares_to_burn),
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
        Vault::at(vault_address).withdraw_private_to_public_exact(from, to, assets, shares_to_burn),
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
        Vault::at(vault_address).withdraw_private_to_private_exact(from, to, assets, shares_to_burn),
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
