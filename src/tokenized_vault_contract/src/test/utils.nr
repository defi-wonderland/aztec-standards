use crate::TokenizedVault;
use aztec::{protocol::address::AztecAddress, test::helpers::test_environment::TestEnvironment};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use std::ops::WrappingSub;
use token_contract::Token;

pub global mint_amount: u128 = 10_000 as u128;

/// @notice Sets up a vault with an asset token and a shares token.
/// Deploys 3 contracts: asset token (with owner as minter), vault (with initializer, admin=owner),
/// shares token (with vault as minter), then calls set_shares on the vault.
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
        AztecAddress::zero(),
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    // Deploy vault with initializer (admin=owner, no shares yet)
    let vault_initializer =
        TokenizedVault::interface().constructor(owner, asset_address, 1, AztecAddress::zero());
    let vault_address = env
        .deploy("@tokenized_vault_contract/TokenizedVault")
        .with_public_initializer(owner, vault_initializer);

    // Deploy shares token with vault as minter
    let shares_initializer = Token::interface().constructor_with_minter(
        "SharesToken00000000000000000000",
        "SHARES0000000000000000000000000",
        18,
        vault_address,
        AztecAddress::zero(),
    );
    let shares_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, shares_initializer);

    // Set the shares token on the vault (admin-only, one-shot)
    env.call_public(owner, TokenizedVault::at(vault_address).set_shares_token(shares_address));

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
        AztecAddress::zero(),
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    // Deploy vault with initializer (admin=owner, no shares yet)
    let vault_initializer =
        TokenizedVault::interface().constructor(owner, asset_address, 1, AztecAddress::zero());
    let vault_address = env
        .deploy("@tokenized_vault_contract/TokenizedVault")
        .with_public_initializer(owner, vault_initializer);

    // Deploy shares token with vault as minter
    let shares_initializer = Token::interface().constructor_with_minter(
        "SharesToken00000000000000000000",
        "SHARES0000000000000000000000000",
        18,
        vault_address,
        AztecAddress::zero(),
    );
    let shares_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, shares_initializer);

    // Mint initial_deposit of assets to owner
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, initial_deposit));

    // Authorize vault to transfer assets from owner
    authorize_transfer_public_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        initial_deposit,
        0,
    );

    // Set shares and make initial deposit (admin-only, one-shot)
    env.call_public(
        owner,
        TokenizedVault::at(vault_address).set_shares_token_with_initial_deposit(
            shares_address,
            initial_deposit,
            owner,
            0,
        ),
    );

    (env, vault_address, owner, recipient, asset_address, shares_address)
}

/// @notice Deploys a vault with initializer but without setting shares (for failure tests)
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
        AztecAddress::zero(),
    );
    let asset_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, asset_initializer);

    // Deploy vault with initializer (admin=owner) but do NOT call set_shares
    let vault_initializer =
        TokenizedVault::interface().constructor(owner, asset_address, 1, AztecAddress::zero());
    let vault_address = env
        .deploy("@tokenized_vault_contract/TokenizedVault")
        .with_public_initializer(owner, vault_initializer);

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

pub unconstrained fn check_total_supply(
    env: TestEnvironment,
    token_address: AztecAddress,
    expected_total_supply: u128,
) {
    let total_supply = get_total_supply(env, token_address);
    assert(total_supply == expected_total_supply, "Total supply is not correct");
}

pub unconstrained fn get_total_supply(env: TestEnvironment, token_address: AztecAddress) -> u128 {
    env.view_public(Token::at(token_address).total_supply())
}

// ====================== Authwit helpers ======================

pub unconstrained fn authorize_transfer_public_to_public(
    env: TestEnvironment,
    token: AztecAddress,
    caller: AztecAddress,
    from: AztecAddress,
    amount: u128,
    nonce: Field,
) {
    let call_interface = Token::at(token).transfer_public_to_public(from, caller, amount, nonce);
    authwit_cheatcodes::add_public_authwit_from_call(env, from, caller, call_interface);
}

pub unconstrained fn authorize_transfer_private_to_public(
    env: TestEnvironment,
    token: AztecAddress,
    caller: AztecAddress,
    from: AztecAddress,
    amount: u128,
    nonce: Field,
) {
    let call_interface = Token::at(token).transfer_private_to_public(from, caller, amount, nonce);
    authwit_cheatcodes::add_private_authwit_from_call(env, from, caller, call_interface);
}

/// @notice Authorizes the vault to burn shares from a user's public balance on the shares token
pub unconstrained fn authorize_burn_public(
    env: TestEnvironment,
    shares_token: AztecAddress,
    vault: AztecAddress,
    from: AztecAddress,
    amount: u128,
    nonce: Field,
) {
    let call_interface = Token::at(shares_token).burn_public(from, amount, nonce);
    authwit_cheatcodes::add_public_authwit_from_call(env, from, vault, call_interface);
}

/// @notice Authorizes the vault to burn shares from a user's private balance on the shares token
pub unconstrained fn authorize_burn_private(
    env: TestEnvironment,
    shares_token: AztecAddress,
    vault: AztecAddress,
    from: AztecAddress,
    amount: u128,
    nonce: Field,
) {
    let call_interface = Token::at(shares_token).burn_private(from, amount, nonce);
    authwit_cheatcodes::add_private_authwit_from_call(env, from, vault, call_interface);
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
    authorize_transfer_public_to_public(env, asset_address, vault_address, minter, amount, 0);

    // Deposit
    env.call_public(
        minter,
        TokenizedVault::at(vault_address).deposit_public_to_public(minter, recipient, amount, 0),
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
    authorize_transfer_public_to_public(env, asset_address, vault_address, minter, amount, 0);

    // Deposit
    env.call_private(
        minter,
        TokenizedVault::at(vault_address).deposit_public_to_private(
            minter,
            recipient,
            amount,
            amount,
            0,
        ),
    );
}

/// @notice Returns the u128 maximum value
pub unconstrained fn max_u128() -> u128 {
    (0 as u128).wrapping_sub(1)
}
