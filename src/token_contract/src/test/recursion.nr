use crate::test::utils;
use crate::Token;
use uint_note::uint_note::UintNote;

use aztec::{
    note::{constants::MAX_NOTES_PER_PAGE, note_getter::view_notes},
    prelude::{AztecAddress, NoteViewerOptions},
    protocol_types::hash::poseidon2_hash,
};

#[test]
unconstrained fn transfer_private_multiple_notes() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, recipient) =
        utils::setup(/* with_account_contracts */ true);

    let notes_amount = U128::from_integer(100);
    let notes_count = 10;
    let total_amount = notes_amount * U128::from_integer(notes_count);
    env.impersonate(owner);
    for i in 0..notes_count {
        utils::mint_to_private(env, token_contract_address, owner, notes_amount);
    }

    // Check that the notes minted to the owner are correct
    env.impersonate(token_contract_address);
    let initial_owner_notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        call_view_private_balance_notes(owner);
    assert(initial_owner_notes.len() == notes_count, "Incorrect minted note count");
    for i in 0..notes_count {
        let note: UintNote = initial_owner_notes.get(i);
        assert(note.get_value() == notes_amount, "Incorrect minted note amount");
    }

    // Transfer tokens
    env.impersonate(owner);
    let transfer_amount = total_amount - notes_amount - U128::from_integer(1);
    let transfer_private_from_call_interface = Token::at(token_contract_address)
        .transfer_private_to_private(owner, recipient, transfer_amount, 0);
    transfer_private_from_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    // Check that the notes still held by the owner are correct
    env.impersonate(token_contract_address);
    let final_owner_notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        call_view_private_balance_notes(owner);
    assert(final_owner_notes.len() == 2, "Incorrect note count"); // 100 UintNote x1 and 1 UintNote x1
    assert(final_owner_notes.get(0).get_value() == notes_amount, "Incorrect note amount");
    assert(
        final_owner_notes.get(1).get_value() == U128::from_integer(1),
        "Incorrect note change amount",
    );

    // Check that the notes generated to the recipient are correct
    env.impersonate(token_contract_address);
    let recipient_notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        call_view_private_balance_notes(recipient);
    assert(recipient_notes.len() == 1, "Incorrect transferred note count"); // 899 UintNote x1
    assert(
        recipient_notes.get(0).get_value() == transfer_amount,
        "Incorrect transferred note amount",
    );

    // Check balances
    utils::check_private_balance(
        token_contract_address,
        owner,
        total_amount - transfer_amount,
    );
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
}

unconstrained fn call_view_private_balance_notes(
    account: AztecAddress,
) -> BoundedVec<UintNote, MAX_NOTES_PER_PAGE> {
    let mut options = NoteViewerOptions::new();
    let private_balances_slot = Token::storage_layout().private_balances.slot;
    let private_balance_slot = poseidon2_hash([private_balances_slot, account.to_field()]);
    let notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> =
        view_notes(private_balance_slot, options.set_offset(0));
    notes
}
