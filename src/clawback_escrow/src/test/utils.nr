use crate::ClawbackEscrow;
use dep::escrow_contract::Escrow;
use dep::token::Token;
use aztec::note::lifecycle::destroy_note;
use aztec::note::note_getter::{MAX_NOTES_PER_PAGE, view_notes};
use aztec::note::note_viewer_options::NoteViewerOptions;
use aztec::{
    oracle::{execution::{get_block_number, get_contract_address}, random::random},
    prelude::AztecAddress,
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
};
use std::test::OracleMock;

pub unconstrained fn setup(
    with_account_contracts: bool,
    mint_amount: U128,
) -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let (owner, recipient) = if with_account_contracts {
        let owner = env.create_account_contract(1);
        let recipient = env.create_account_contract(2);
        (owner, recipient)
    } else {
        let owner = env.create_account(1);
        let recipient = env.create_account(2);
        (owner, recipient)
    };

    env.impersonate(owner);

    // Deploy token contract
    let initializer_call_interface = Token::interface().constructor(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
    );
    let token_contract = env.deploy("./@token_contract", "Token").with_public_void_initializer(
        initializer_call_interface,
    );

    let token_contract_address = token_contract.to_address();
    env.advance_block_by(1);

    // Mint private tokens to owner
    mint_to_private(&mut env, token_contract_address, owner, mint_amount);

    // Deploy clawback escrow contract
    env.impersonate(owner);
    let clawback_escrow_contract = env.deploy_self("ClawbackEscrow").without_initializer();
    let clawback_escrow_address = clawback_escrow_contract.to_address();
    env.advance_block_by(1);

    // Deploy the escrow
    let escrow_secret = 42069;
    let escrow_contract_account = cheatcodes::add_account(escrow_secret);
    let initializer_call_escrow = Escrow::interface().constructor(clawback_escrow_address);

    let escrow_contract = env
        .deploy_with_public_keys("./@escrow_contract", "Escrow", escrow_secret)
        .with_private_initializer(initializer_call_escrow);
    let escrow_address = escrow_contract.to_address();
    env.advance_block_by(1);

    dep::aztec::oracle::debug_log::debug_log_format(
        "TOKEN ADDRESS: {0}",
        [token_contract_address.to_field()],
    );
    dep::aztec::oracle::debug_log::debug_log_format(
        "CLAWBACK ADDRESS: {0}",
        [clawback_escrow_address.to_field()],
    );
    dep::aztec::oracle::debug_log::debug_log_format(
        "ESCROW ADDRESS: {0}",
        [escrow_address.to_field()],
    );

    // Fund the escrow
    transfer_in_private(
        &mut env,
        owner,
        token_contract_address,
        escrow_address,
        mint_amount,
    );

    (&mut env, clawback_escrow_address, escrow_address, token_contract_address, owner, recipient)
}

pub unconstrained fn mint_to_private(
    env: &mut TestEnvironment,
    token_contract_address: AztecAddress,
    recipient: AztecAddress,
    amount: U128,
) {
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    let from = recipient; // we are setting from to recipient because of TODO(#9887)
    Token::at(token_contract_address).mint_to_private(from, recipient, amount).call(
        &mut env.private(),
    );

    env.advance_block_by(1);
}

pub unconstrained fn transfer_in_private(
    env: &mut TestEnvironment,
    from: AztecAddress,
    token_contract_address: AztecAddress,
    recipient: AztecAddress,
    amount: U128,
) {
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    env.impersonate(from);
    Token::at(token_contract_address).transfer_private_to_private(from, recipient, amount, 0).call(
        &mut env.private(),
    );

    env.advance_block_by(1);
}

pub unconstrained fn check_private_balance(
    token_contract_address: AztecAddress,
    address: AztecAddress,
    address_amount: U128,
) {
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(token_contract_address);
    // Direct call to unconstrained
    let balance_of_private = Token::balance_of_private(address);
    assert(balance_of_private == address_amount, "Private balance is not correct");
    cheatcodes::set_contract_address(current_contract_address);
}
