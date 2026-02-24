use crate::Token;
use aztec::{
    note::{constants::MAX_NOTES_PER_PAGE, note_viewer_options::NoteViewerOptions},
    oracle::random::random,
    protocol::{address::AztecAddress, traits::Packable},
    state_vars::{OwnedStateVariable, PrivateSet},
    test::helpers::test_environment::TestEnvironment,
};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use std::ops::WrappingSub;
use std::test::OracleMock;
use uint_note::UintNote;

pub global mint_amount: u128 = 10_000 as u128;

pub unconstrained fn setup_with_initial_supply(
    with_account_contracts: bool,
    initial_supply: u128,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
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

    let token_contract_address =
        deploy_token_with_initial_supply(&mut env, owner, initial_supply, owner);

    (env, token_contract_address, owner, recipient)
}

pub unconstrained fn setup_with_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let (owner, recipient, minter) = if with_account_contracts {
        let owner = env.create_contract_account();
        let recipient = env.create_contract_account();
        let minter = env.create_contract_account();
        (owner, recipient, minter)
    } else {
        let owner = env.create_light_account();
        let recipient = env.create_light_account();
        let minter = env.create_light_account();
        (owner, recipient, minter)
    };

    let token_contract_address = deploy_token_with_minter(&mut env, owner, minter);

    (env, token_contract_address, owner, recipient, minter)
}

pub unconstrained fn setup_with_asset(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
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

    // Deploy asset token
    let asset_initializer_call_interface = Token::interface().constructor_with_minter(
        "AssetToken000000000000000000000",
        "ASSET00000000000000000000000000",
        6, // TODO: Test 18 decimals once overflows are handled correctly in asset-share conversion
        owner,
        AztecAddress::zero(),
    );
    let asset_contract_address = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        asset_initializer_call_interface,
    );

    // Deploy token with asset
    let vault_initializer_call_interface = Token::interface().constructor_with_asset(
        "Vault00000000000000000000000000",
        "VAULT00000000000000000000000000",
        18,
        asset_contract_address,
        1,
        AztecAddress::zero(),
    );
    let vault_contract_address = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        vault_initializer_call_interface,
    );

    (env, vault_contract_address, owner, recipient, asset_contract_address)
}

// TODO: When salt setting in env deployment is supported we can precompute the vault address and
// compute the authwit before deployment. Deployment use constructor_with_asset for now.

pub unconstrained fn setup_with_asset_initial_deposit(
    with_account_contracts: bool,
    initial_deposit: u128,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Use setup_with_minter to get the asset token and accounts
    let (mut env, asset_contract_address, owner, recipient, minter) =
        setup_with_minter(with_account_contracts);

    // Mint initial_deposit to owner
    env.call_public(minter, Token::at(asset_contract_address).mint_to_public(owner, initial_deposit));

    // Deploy vault with constructor_with_asset
    let vault_initializer_call_interface = Token::interface().constructor_with_asset(
        "Vault00000000000000000000000000",
        "VAULT00000000000000000000000000",
        18,
        asset_contract_address,
        1,
        AztecAddress::zero(),
    );
    let vault_contract_address = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        vault_initializer_call_interface,
    );

    // Authorize vault to transfer assets from owner
    authorize_transfer_public_to_public(
        env,
        asset_contract_address,
        vault_contract_address,
        owner,
        initial_deposit,
        0,
    );

    // Deposit to vault, with shares going to vault address itself (locked shares)
    env.call_public(
        owner,
        Token::at(vault_contract_address).deposit_public_to_public(
            owner,
            vault_contract_address,
            initial_deposit,
            0,
        ),
    );

    (env, vault_contract_address, owner, recipient, asset_contract_address, minter)
}

pub unconstrained fn deploy_token_with_initial_supply(
    env: &mut TestEnvironment,
    owner: AztecAddress,
    initial_supply: u128,
    to: AztecAddress,
) -> AztecAddress {
    // Deploy token contract
    let initializer_call_interface = Token::interface().constructor_with_initial_supply(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
        initial_supply,
        to,
        AztecAddress::zero(),
    );
    let token_contract_address = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        initializer_call_interface,
    );

    token_contract_address
}

pub unconstrained fn deploy_token_with_minter(
    env: &mut TestEnvironment,
    owner: AztecAddress,
    minter: AztecAddress,
) -> AztecAddress {
    // Deploy token contract
    let initializer_call_interface = Token::interface().constructor_with_minter(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
        minter,
        AztecAddress::zero(),
    );
    let token_contract_address = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        initializer_call_interface,
    );

    token_contract_address
}

pub unconstrained fn setup_and_mint_to_public_with_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup
    let (env, token_contract_address, owner, recipient, minter) =
        setup_with_minter(with_account_contracts);

    // Mint some tokens
    env.call_public(minter, Token::at(token_contract_address).mint_to_public(owner, mint_amount));

    (env, token_contract_address, owner, recipient, minter)
}

pub unconstrained fn setup_and_mint_to_public_without_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    // Setup
    let (env, token_contract_address, owner, recipient) =
        setup_with_initial_supply(with_account_contracts, mint_amount);

    (env, token_contract_address, owner, recipient)
}

pub unconstrained fn setup_and_mint_to_private_with_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (env, token_contract_address, owner, recipient, minter) =
        setup_with_minter(with_account_contracts);

    // Mint some tokens
    mint_to_private(env, token_contract_address, owner, mint_amount, minter);

    (env, token_contract_address, owner, recipient, minter)
}

pub unconstrained fn setup_and_mint_to_private_without_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    // Setup
    let (env, token_contract_address, owner, recipient) =
        setup_with_initial_supply(with_account_contracts, mint_amount);

    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_public_to_private(owner, owner, mint_amount, 0),
    );

    (env, token_contract_address, owner, recipient)
}

pub unconstrained fn mint_to_private(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
    caller: AztecAddress,
) {
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    env.call_private(caller, Token::at(token_contract_address).mint_to_private(recipient, amount));
}

pub unconstrained fn transfer_in_private(
    env: TestEnvironment,
    from: AztecAddress,
    token_contract_address: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
) {
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    env.call_private(
        from,
        Token::at(token_contract_address).transfer_private_to_private(from, recipient, amount, 0),
    );
}

pub unconstrained fn check_public_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
    address_amount: u128,
) {
    let amount: u128 = get_public_balance(env, token_contract_address, address);
    assert(amount == address_amount, "Public balance is not correct");
}

pub unconstrained fn get_public_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
) -> u128 {
    let amount = env.view_public(Token::at(token_contract_address).balance_of_public(address));
    amount
}

pub unconstrained fn check_total_supply(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    expected_total_supply: u128,
) {
    let total_supply: u128 = get_total_supply(env, token_contract_address);
    assert(total_supply == expected_total_supply, "Total supply is not correct");
}

pub unconstrained fn get_total_supply(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
) -> u128 {
    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    total_supply
}

pub unconstrained fn check_private_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
    address_amount: u128,
) {
    let balance_of_private = get_private_balance(env, token_contract_address, address);
    assert(balance_of_private == address_amount, "Private balance is not correct");
}

pub unconstrained fn get_private_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
) -> u128 {
    let amt = env.simulate_utility(Token::at(token_contract_address).balance_of_private(address));
    amt
}

pub unconstrained fn get_private_balance_notes(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    account: AztecAddress,
    offset: u32,
) -> BoundedVec<UintNote, MAX_NOTES_PER_PAGE> {
    let notes = env.utility_context_at(token_contract_address, |context| {
        let options =
            NoteViewerOptions::<UintNote, <UintNote as Packable>::N>::new().set_offset(offset);
        let private_balances_slot = Token::storage_layout().private_balances.slot;
        let set: PrivateSet<UintNote, _> =
            OwnedStateVariable::new(context, private_balances_slot, account);
        let notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> = set.view_notes(options);
        notes
    });

    notes
}

/// @notice Retrieves whether a commitment has been stored in the storage of the target contract
pub unconstrained fn _commitment_storage_read(
    env: TestEnvironment,
    target_contract_address: AztecAddress,
    commitment: Field,
) -> bool {
    // set target contract address
    let value = env.public_context_at(target_contract_address, |context| {
        let value: bool = context.storage_read(commitment);
        value
    });
    value
}

/// @notice Sets private authwit for the `transfer_private_to_public` method. `caller` is also the recipient.
pub unconstrained fn authorize_transfer_private_to_public(
    env: TestEnvironment,
    token: AztecAddress,
    caller: AztecAddress,
    from: AztecAddress,
    amount: u128,
    nonce: Field,
) {
    let transfer_private_to_public_call_interface =
        Token::at(token).transfer_private_to_public(from, caller, amount, nonce);
    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        from,
        caller,
        transfer_private_to_public_call_interface,
    );
}

/// @notice Sets public authwit for the `transfer_private_to_public` method. `caller` is also the recipient.
pub unconstrained fn authorize_transfer_public_to_public(
    env: TestEnvironment,
    token: AztecAddress,
    caller: AztecAddress,
    from: AztecAddress,
    amount: u128,
    nonce: Field,
) {
    let transfer_public_to_public_call_interface =
        Token::at(token).transfer_public_to_public(from, caller, amount, nonce);
    authwit_cheatcodes::add_public_authwit_from_call(
        env,
        from,
        caller,
        transfer_public_to_public_call_interface,
    );
}

// While authwits authorize a contract to perform an action, spending private notes still requires
// knowledge of the note secrets. For private tokens, the note owner must be involved in the
// transaction -- they cannot simply give another user an authwit and have that user spend the notes
// independently. We deploy a proxy contract so that msg_sender in the target differs from the
// caller, which is the condition that triggers authwit validation. We can't use another account for
// this, since different scopes are enforced by TXE.
pub unconstrained fn setup_and_mint_to_private_with_proxy() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, token_contract_address, owner, recipient) =
        setup_and_mint_to_private_without_minter(/* with_account_contracts */ true);
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
    (env, token_contract_address, owner, recipient, proxy)
}

pub unconstrained fn setup_and_mint_to_public_with_proxy() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, token_contract_address, owner, recipient) =
        setup_and_mint_to_public_without_minter(/* with_account_contracts */ true);
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
    (env, token_contract_address, owner, recipient, proxy)
}

/// @notice Returns the u128 maximum value
pub unconstrained fn max_u128() -> u128 {
    (0 as u128).wrapping_sub(1)
}
