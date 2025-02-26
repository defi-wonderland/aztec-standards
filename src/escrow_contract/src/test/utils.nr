use crate::Escrow;
use aztec::{
    oracle::{
        execution::{get_block_number, get_contract_address},
        random::random,
        storage::storage_read,
    },
    prelude::{AztecAddress, NoteHeader},
    protocol_types::storage::map::derive_storage_slot_in_map,
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
    note::{
        lifecycle::{create_note, destroy_note_unsafe},
        note_getter::{get_notes, view_notes},
        note_getter_options::NoteStatus,
        note_interface::NoteType,
        retrieved_note::RetrievedNote,
        constants::MAX_NOTES_PER_PAGE,
    },
};
use std::test::OracleMock;
use dep::address_note::address_note::AddressNote;

pub unconstrained fn setup(
    with_account_contracts: bool,
) -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let (deployer, owner, recipient) = if with_account_contracts {
        let deployer = env.create_account_contract(1);
        let owner = env.create_account_contract(2);
        let recipient = env.create_account_contract(3);
        (deployer, owner, recipient)
    } else {
        let deployer = env.create_account(1);
        let owner = env.create_account(2);
        let recipient = env.create_account(3);
        (deployer, owner, recipient)
    };

    // Start the test in the account contract address
    env.impersonate(deployer);

    // Deploy escrow contract
    let initializer_call_interface = Escrow::interface().constructor(owner);
    let escrow_contract = env.deploy_self("Escrow").with_private_initializer(initializer_call_interface);
    let escrow_contract_address = escrow_contract.to_address();
    env.advance_block_by(1);
    (&mut env, escrow_contract_address, deployer, owner, recipient)
}

pub unconstrained fn call_view_owner_note() -> pub AddressNote {
    let mut options = NoteViewerOptions::new();
    let owner_slot: Escrow::storage_layout().owner.slot;
    let notes: BoundedVec<AddressNote, MAX_NOTES_PER_PAGE> = view_notes(owner_slot, options);

    notes.get(0)
}
