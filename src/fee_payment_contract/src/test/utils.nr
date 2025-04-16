use crate::FPC;
use aztec::{
    oracle::execution::get_contract_address,
    prelude::AztecAddress,
    protocol_types::storage::map::derive_storage_slot_in_map,
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
};
use token::Token;
use uint_note::uint_note::UintNote;

use authwit::cheatcodes as authwit_cheatcodes;

//=================================================================
// Setup Functions
//=================================================================

/// @notice Sets up the testing environment, deploying FPC and Token contracts.
/// @return env The test environment.
/// @return fpc_contract_address The address of the deployed FPC contract.
/// @return admin The admin account address.
/// @return user The user account contract address.
/// @return token The address of the deployed Token contract.
pub unconstrained fn setup() -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();

    let admin = env.create_account(1);
    let user = env.create_account_contract(2);
    let token = deploy_token_with_minter(&mut env, admin);

    env.impersonate(admin);

    let initializer_call_interface = FPC::interface().constructor(token, admin);

    let fpc_contract = env.deploy("./@fee_payment_contract", "FPC").with_public_void_initializer(
        initializer_call_interface,
    );

    env.advance_block_by(1);

    (&mut env, fpc_contract.to_address(), admin, user, token)
}

/// @notice Deploys a Token contract with a specified minter.
/// @param env The test environment.
/// @param minter The address designated as the token minter.
/// @return The address of the deployed Token contract.
pub unconstrained fn deploy_token_with_minter(
    env: &mut TestEnvironment,
    minter: AztecAddress,
) -> AztecAddress {
    env.impersonate(minter);

    // Deploy token contract
    let initializer_call_interface = Token::interface().constructor_with_minter(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
        minter,
    );
    let token_contract = env.deploy("./@token_contract", "Token").with_public_void_initializer(
        initializer_call_interface,
    );
    env.advance_block_by(1);

    token_contract.to_address()
}

//=================================================================
// Minting and Note Management Functions
//=================================================================

/// @notice Mints public tokens to a recipient. Requires minter impersonation.
/// @param env The test environment.
/// @param token_contract_address The address of the Token contract.
/// @param minter The address authorized to mint tokens.
/// @param recipient The address receiving the minted public tokens.
/// @param amount The amount of tokens to mint.
pub unconstrained fn mint_to_public(
    env: &mut TestEnvironment,
    token_contract_address: AztecAddress,
    minter: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
) {
    // Mint tokens to user
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_public(recipient, amount).call(&mut env.public());

    env.advance_block_by(1);
}

/// @notice Mints private tokens to a recipient. Requires minter impersonation.
/// @param env The test environment.
/// @param token_contract_address The address of the Token contract.
/// @param minter The address authorized to mint tokens (also pays fee).
/// @param recipient The address receiving the minted private tokens (notes).
/// @param amount The amount of tokens to mint.
pub unconstrained fn mint_to_private(
    env: &mut TestEnvironment,
    token_contract_address: AztecAddress,
    minter: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
) {
    // Mint tokens to user
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_private(minter, recipient, amount).call(
        &mut env.private(),
    );

    env.advance_block_by(1);
}

/// @notice Adds a private token note directly to storage using cheatcodes.
/// @param env The test environment.
/// @param token_contract_address The address of the Token contract where the note belongs.
/// @param owner The owner of the note.
/// @param amount The value of the note.
/// @param note_randomness The randomness field for the note.
pub unconstrained fn add_token_note(
    env: &mut TestEnvironment,
    token_contract_address: AztecAddress,
    owner: AztecAddress,
    amount: u128,
    note_randomness: Field,
) {
    let balances_owner_slot =
        derive_storage_slot_in_map(Token::storage_layout().private_balances.slot, owner);

    env.add_note(
        UintNote { value: amount, owner: owner, randomness: note_randomness },
        balances_owner_slot,
        token_contract_address,
    );

    env.advance_block_by(1);
}

//=================================================================
// Balance Checking Functions
//=================================================================

/// @notice Gets the private balance of an account via direct unconstrained call.
/// @param token_contract_address The address of the Token contract.
/// @param address The address whose private balance is being queried.
/// @return The private token balance.
pub unconstrained fn get_private_balance(
    token_contract_address: AztecAddress,
    address: AztecAddress,
) -> u128 {
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(token_contract_address);
    // Direct call to unconstrained
    let balance = Token::balance_of_private(address);
    cheatcodes::set_contract_address(current_contract_address);
    balance
}

/// @notice Checks if the private balance matches an expected amount via direct unconstrained call.
/// @param token_contract_address The address of the Token contract.
/// @param address The address whose private balance is being checked.
/// @param address_amount The expected private balance.
pub unconstrained fn check_private_balance(
    token_contract_address: AztecAddress,
    address: AztecAddress,
    address_amount: u128,
) {
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(token_contract_address);
    // Direct call to unconstrained
    let balance_of_private = Token::balance_of_private(address);
    assert(balance_of_private == address_amount, "Private balance is not correct");
    cheatcodes::set_contract_address(current_contract_address);
}

/// @notice Gets the public balance of an account via a view call.
/// @param env The test environment.
/// @param token_contract_address The address of the Token contract.
/// @param account The address whose public balance is being queried.
/// @return The public token balance.
pub unconstrained fn public_token_balance(
    env: &mut TestEnvironment,
    token_contract_address: AztecAddress,
    account: AztecAddress,
) -> u128 {
    Token::at(token_contract_address).balance_of_public(account).view(&mut env.public())
}

//=================================================================
// Authwit Preparation Functions
//=================================================================

/// @notice Prepares an authwit for a public-to-public token transfer using cheatcodes.
/// @param token_contract_address The address of the Token contract.
/// @param from The address initiating the transfer (authwit provider).
/// @param caller The address that will call the transfer function.
/// @param amount The amount of tokens to transfer.
/// @param nonce The nonce for the transfer action.
pub unconstrained fn prepare_public_transfer_authwit(
    token_contract_address: AztecAddress,
    from: AztecAddress,
    caller: AztecAddress,
    amount: u128,
    nonce: Field,
) {
    // Prepare authwit for public transfer call
    let public_to_public_transfer_call_interface =
        Token::at(token_contract_address).transfer_public_to_public(from, caller, amount, nonce);

    authwit_cheatcodes::add_public_authwit_from_call_interface(
        from,
        caller,
        public_to_public_transfer_call_interface,
    );
}

/// @notice Prepares an authwit for a private-to-public token transfer using cheatcodes.
/// @param token_contract_address The address of the Token contract.
/// @param from The address initiating the transfer (authwit provider).
/// @param caller The address that will call the transfer function.
/// @param amount The amount of tokens to transfer.
/// @param nonce The nonce for the transfer action.
pub unconstrained fn prepare_private_transfer_authwit(
    token_contract_address: AztecAddress,
    from: AztecAddress,
    caller: AztecAddress,
    amount: u128,
    nonce: Field,
) {
    // Prepare authwit for public transfer call
    let private_to_public_transfer_call_interface =
        Token::at(token_contract_address).transfer_private_to_public(from, caller, amount, nonce);

    authwit_cheatcodes::add_private_authwit_from_call_interface(
        from,
        caller,
        private_to_public_transfer_call_interface,
    );
}
