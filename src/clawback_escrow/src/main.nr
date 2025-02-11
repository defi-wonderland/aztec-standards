use dep::aztec::macros::aztec;
mod test;

#[aztec]
pub contract ClawbackEscrow {
    use dep::aztec::{
        context::PrivateContext,
        encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note,
        macros::{functions::private, notes::note, storage::storage},
        note::{
            note_header::NoteHeader, note_interface::NullifiableNote,
            utils::compute_note_hash_for_nullify,
        },
        protocol_types::{
            constants::GENERATOR_INDEX__NOTE_NULLIFIER,
            hash::poseidon2_hash_with_separator,
            traits::{Packable, Serialize, ToField},
        },
    };
    use dep::aztec::prelude::{AztecAddress, Map, PrivateImmutable};

    use dep::escrow_contract::Escrow;

    #[note]
    #[derive(Serialize)]
    pub struct ClawbackEscrowNote {
        sender: AztecAddress,
        receiver: AztecAddress,
        // NOTE: escrow address has randomness in it (acts as privacy salt)
        escrow: AztecAddress,
    }

    // TODO: why do we need NullifiableNote for PrivateImmutable?
    impl NullifiableNote for ClawbackEscrowNote {
        fn compute_nullifier(self, _: &mut PrivateContext, note_hash_for_nullify: Field) -> Field {
            poseidon2_hash_with_separator(
                [note_hash_for_nullify, self.escrow.to_field()],
                GENERATOR_INDEX__NOTE_NULLIFIER as Field,
            )
        }

        unconstrained fn compute_nullifier_without_context(self) -> Field {
            let note_hash_for_nullify = compute_note_hash_for_nullify(self);
            poseidon2_hash_with_separator(
                [note_hash_for_nullify, self.escrow.to_field()],
                GENERATOR_INDEX__NOTE_NULLIFIER as Field,
            )
        }
    }

    impl ClawbackEscrowNote {
        pub fn new(sender: AztecAddress, receiver: AztecAddress, escrow: AztecAddress) -> Self {
            ClawbackEscrowNote { sender, receiver, escrow, header: NoteHeader::empty() }
        }
    }

    #[storage]
    struct Storage<Context> {
        escrows: Map<AztecAddress, PrivateImmutable<ClawbackEscrowNote, Context>, Context>,
    }

    #[private]
    fn create_clawback_escrow(escrow: AztecAddress, receiver: AztecAddress) {
        // This will revert if the Clawback Escrow is not the owner of the escrow
        let _ = Escrow::at(escrow).leak_keys(receiver);

        let sender = context.msg_sender();
        let mut note = ClawbackEscrowNote::new(sender, receiver, escrow);

        // Check that a clawback escrow has not been created for that escrow
        // TODO: check that this isn't needed (initialize nullifies the `at(escrow)` storage slot)
        let nullifier = std::hash::pedersen_hash([escrow.to_field()]); // derive nullifier from escrow address
        context.push_nullifier(nullifier);

        let note_insertion = storage.escrows.at(escrow).initialize(&mut note);

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

    #[contract_library_method]
    fn _find_clawback_note(
        storage: Storage<&mut PrivateContext>,
        escrow: AztecAddress,
    ) -> ClawbackEscrowNote {
        // TODO: check that it doesn't nullify the PrivateImmutable note
        let note = storage.escrows.at(escrow).get_note();
        note
    }
}
