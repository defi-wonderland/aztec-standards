use dep::aztec::macros::aztec;
mod test;
mod types;

#[aztec]
pub contract ClawbackEscrow {
    use crate::types::clawback_escrow_note::ClawbackEscrowNote;
    use dep::aztec::{
        context::PrivateContext,
        encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note,
        macros::{functions::private, notes::note, storage::storage},
        note::{
            note_getter_options::NoteGetterOptions, note_header::NoteHeader,
            note_interface::NoteProperties,
        },
        oracle::random::random,
        prelude::AztecAddress,
        protocol_types::{
            constants::GENERATOR_INDEX__NOTE_NULLIFIER,
            traits::{Hash, Packable, Serialize, ToField},
        },
        state_vars::PrivateSet,
        utils::comparison::Comparator,
    };
    use dep::escrow_contract::Escrow;

    #[storage]
    struct Storage<Context> {
        escrows: PrivateSet<ClawbackEscrowNote, Context>,
    }

    /** ==========================================================
     * ======================= PRIVATE ===========================
     * ======================================================== */

    #[private]
    fn create_clawback_escrow(escrow: AztecAddress, receiver: AztecAddress) {
        // This will revert if the Clawback Escrow is not the owner of the escrow
        // TODO: temporary disable leaking keys
        // Escrow::at(escrow).leak_keys(receiver).call(&mut context);

        let sender = context.msg_sender();
        let mut note = ClawbackEscrowNote::new(sender, receiver, escrow);

        // Check that a clawback escrow has not been created for that escrow
        let nullifier = std::hash::pedersen_hash([escrow.to_field()]); // derive nullifier from escrow address
        context.push_nullifier(nullifier);

        let note_insertion = storage.escrows.insert(&mut note);

        // Emit the note for the sender
        note_insertion.emit(encode_and_encrypt_note(&mut context, sender, sender));

        // Emit the note for the receiver
        note_insertion.emit(encode_and_encrypt_note(&mut context, receiver, sender));
    }

    #[private]
    fn claim(escrow: AztecAddress, token: AztecAddress, amount: U128) {
        let caller = context.msg_sender();

        // There should only be one note per escrow
        let note = _find_clawback_note(storage, escrow);

        assert(note.escrow == escrow, "Invalid escrow address");
        assert(caller == note.receiver, "Only receiver can claim");

        Escrow::at(escrow).withdraw(token, amount, note.receiver).call(&mut context);
    }

    #[private]
    fn clawback(escrow: AztecAddress, token: AztecAddress, amount: U128) {
        let caller = context.msg_sender();

        // There should only be one note per escrow
        let note = _find_clawback_note(storage, escrow);

        assert(note.escrow == escrow, "Invalid escrow address");
        assert(caller == note.sender, "Only sender can clawback");

        Escrow::at(escrow).withdraw(token, amount, caller).call(&mut context);
    }

    /** ==========================================================
     * ======================== LIBRARIES ========================
     * ======================================================== */

    #[contract_library_method]
    fn _find_clawback_note(
        storage: Storage<&mut PrivateContext>,
        escrow: AztecAddress,
    ) -> ClawbackEscrowNote {
        let options = NoteGetterOptions::new()
            .select(ClawbackEscrowNote::properties().escrow, Comparator.EQ, escrow)
            .set_limit(1);
        let notes = storage.escrows.get_notes(options);

        // We revert if there is no note in the filter so we can probably unwrap directly
        let unwrapped_note = notes.get_unchecked(0);

        assert(unwrapped_note.escrow == escrow, "Invalid escrow address");
        unwrapped_note
    }
}
