use crate::Escrow;
use crate::types::account_note::AccountNote;
use aztec::{
    prelude::{AztecAddress, NoteViewerOptions},
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
    note::{
        note_getter::{view_notes},
        constants::MAX_NOTES_PER_PAGE,
    },
};
use dep::token::test::utils as token_utils;

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
    let token_contract_address = token_utils::deploy_token(env, owner);

    // Mint private tokens to escrow contract
    env.impersonate(owner);
    token_utils::mint_to_private(env, token_contract_address, escrow_address, mint_amount);

    token_utils::check_private_balance(
        token_contract_address,
        escrow_address,
        mint_amount,
    );

    dep::aztec::oracle::debug_log::debug_log_format(
        "TOKEN ADDRESS: {0}",
        [token_contract_address.to_field()],
    );

    (env, escrow_address, owner, recipient, token_contract_address, escrow_secret)
}

pub unconstrained fn call_view_owner_note() -> pub AccountNote {
    let mut options = NoteViewerOptions::new();
    let owner_slot = Escrow::storage_layout().owner.slot;
    let notes: BoundedVec<AccountNote, MAX_NOTES_PER_PAGE> = view_notes(owner_slot, options);

    notes.get(0)
}
