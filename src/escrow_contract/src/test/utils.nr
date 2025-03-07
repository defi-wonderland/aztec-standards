use crate::Escrow;
use crate::types::account_note::AccountNote;
use dep::token::Token;
use aztec::{
    oracle::{
        execution::{get_contract_address},
    },
    prelude::{AztecAddress, NoteViewerOptions},
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
    note::{
        note_getter::{view_notes},
        constants::MAX_NOTES_PER_PAGE,
    },
};
use std::test::OracleMock;

pub unconstrained fn setup(
    with_account_contracts: bool,
) -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress, Field) {
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
    // Start the test in the account contract address
    env.impersonate(owner);

    // Deploy escrow contract
    let escrow_secret = 42069;
    let escrow_contract_account = cheatcodes::add_account(escrow_secret);
    let initializer_call_escrow =
        Escrow::interface().constructor(owner, escrow_secret);

    let escrow_contract = env
        .deploy_self_with_public_keys("Escrow", escrow_secret)
        .with_private_initializer(initializer_call_escrow);
    let escrow_address = escrow_contract.to_address();

    env.advance_block_by(1);

    (&mut env, escrow_address, owner, recipient, escrow_secret)
}

pub unconstrained fn setup_and_mint(
    with_account_contracts: bool,
    mint_amount: U128,
) -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, Field) {
    let (env, escrow_address, owner, recipient, escrow_secret) = setup(with_account_contracts);
    
    // Deploy token contract
    let initializer_call_interface = Token::interface().constructor(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
    );
    let token_contract = env.deploy("./@token_contract", "Token").with_public_void_initializer(
        initializer_call_interface,
    );

    let token_address = token_contract.to_address();
    env.advance_block_by(1);

    // Mint private tokens to escrow contract
    Token::at(token_address).mint_to_private(escrow_address, escrow_address, mint_amount).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    check_private_balance(token_address, escrow_address, mint_amount);

    dep::aztec::oracle::debug_log::debug_log_format(
        "TOKEN ADDRESS: {0}",
        [token_address.to_field()],
    );

    (env, escrow_address, owner, recipient, token_address, escrow_secret)
}

pub unconstrained fn call_view_owner_note() -> pub AccountNote {
    let mut options = NoteViewerOptions::new();
    let owner_slot = Escrow::storage_layout().owner.slot;
    let notes: BoundedVec<AccountNote, MAX_NOTES_PER_PAGE> = view_notes(owner_slot, options);

    notes.get(0)
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
