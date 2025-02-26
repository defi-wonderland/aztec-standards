use crate::ClawbackEscrow;
use crate::test::utils;
use crate::types::clawback_escrow_note::ClawbackEscrowNote;
use dep::address_note::address_note::AddressNote;
use dep::escrow_contract::Escrow;
use aztec::note::lifecycle::destroy_note;
use aztec::note::note_getter::{MAX_NOTES_PER_PAGE, view_notes};
use aztec::note::note_viewer_options::NoteViewerOptions;
use aztec::{
    oracle::{
        execution::{get_block_number, get_contract_address},
        random::random,
        storage::storage_read,
    },
    prelude::{AztecAddress, NoteHeader},
    protocol_types::storage::map::derive_storage_slot_in_map,
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
};

#[test]
unconstrained fn create_clawback_escrow() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, clawback_escrow_contract_address, escrow_contract_address, token_contract_address, owner, recipient) =
        utils::setup(true, mint_amount);

    // Create the clawback escrow
    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .create_clawback_escrow(escrow_contract_address, recipient)
        .call(&mut env.private());

    env.advance_block_by(1);

    utils::check_private_balance(token_contract_address, escrow_contract_address, mint_amount);

    env.impersonate(recipient);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .claim(escrow_contract_address, token_contract_address, mint_amount)
        .call(&mut env.private());

    utils::check_private_balance(token_contract_address, recipient, mint_amount);
}

#[test(should_fail_with = "Rejecting tx for emitting duplicate nullifiers")]
unconstrained fn escrow_can_only_have_one_clawback_escrow() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, clawback_escrow_contract_address, escrow_contract_address, _, owner, recipient) =
        utils::setup(true, mint_amount);

    // Create the clawback escrow
    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .create_clawback_escrow(escrow_contract_address, recipient)
        .call(&mut env.private());

    env.advance_block_by(1);

    // Create the clawback escrow
    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .create_clawback_escrow(escrow_contract_address, recipient)
        .call(&mut env.private());
}

