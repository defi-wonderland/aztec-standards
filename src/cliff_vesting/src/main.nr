use dep::aztec::macros::aztec;

#[aztec]
pub contract CliffVesting {
    use dep::aztec::{
        encrypted_logs::encrypted_note_emission::encode_and_encrypt_note,
        note::note_getter_options::NoteGetterOptions,
        macros::{functions::{initializer, private}, storage::storage},
        note::{Note, NoteHeader},
    };
    use dep::aztec::prelude::{AztecAddress, PrivateImmutable};

    use dep::address_note::address_note::AddressNote;
    use dep::token::Token;

    use crate::escrow_contract;

    #[storage]
    struct Storage<Context> {
        escrows: PrivateSet<CliffVestingNote, Context>,
    }

    #[note]
    pub struct CliffVestingNote {
        sender: AztecAddress,
        receiver: AztecAddress,
        escrow: AztecAddress,
        vesting: U128,
        randomness: Field
    }

    impl CliffVestingNote {
        pub fn new(
            sender: AztecAddress,
            receiver: AztecAddress,
            escrow: AztecAddress,
            vesting: U128,
            randomness: Field,
        ) -> Self {
            CliffVestingNote { 
                sender,
                receiver, 
                escrow,
                vesting,
                randomness,
                header: NoteHeader::empty() 
            }
        }
    }

    pub fn filter_note_escrow(
        notes: [Option<CliffVestingNote>; MAX_NOTE_HASH_READ_REQUESTS_PER_CALL],
        escrow: AztecAddress,
    ) -> [Option<CliffVestingNote>; MAX_NOTE_HASH_READ_REQUESTS_PER_CALL] {
        let mut selected = [Option::none(); MAX_NOTE_HASH_READ_REQUESTS_PER_CALL];

        for i in 0..notes.len() {
            if notes[i].is_some() {
                let note = notes[i].unwrap_unchecked();
                if note.escrow == escrow {
                    selected[0] = Option::some(note);
                    selected
                }
            }
        }

        assert(false, "No cliff vesting found for escrow");
    }

    #[private]
    fn create_cliff_vesting(escrow: AztecAddress, receiver: AztecAddress, vesting: U128) {
        let escrow_owner = Escrow::at(escrow).owner();
        assert(escrow_owner == context.this_address(), "Cliff vesting is not owner");

        let sender = context.msg_sender();
        let note = CliffVestingNote::new(
            sender, 
            receiver, 
            escrow, 
            vesting, 
            context.randomness()
        );

        // Do we need to check if there is already a cliff vesting created for this escrow?
        let note_insertion = storage.escrows.insert(&mut context, note);

        // Emit the note for the sender
        note_insertion.emit(encode_and_encrypt_note(
            &mut context,
            sender,
            sender,
        ));

        // Emit the note for the receiver
        note_insertion.emit(encode_and_encrypt_note(
            &mut context,
            receiver,
            sender,
        ));
    }

    #[private]
    fn claim(escrow: AztecAddress) {
        let caller = context.msg_sender();
        
        // Find and remove the note
        // There should only be one note per escrow
        let note = find_and_remove_cliff_note(escrow);
            
        assert(note.escrow == escrow, "Invalid escrow address");
        assert(caller == note.receiver, "Only receiver can claim");

        Escrow::at(escrow).withdraw(note.receiver).call(&mut context);
    }

    #[private]
    fn clawback(escrow: AztecAddress) {
        let caller = context.msg_sender();
        
        // Find and remove the note
        // There should only be one note per escrow
        let note = find_and_remove_cliff_note(escrow);
            
        assert(note.escrow == escrow, "Invalid escrow address");
        assert(caller == note.sender, "Only sender can clawback");

        Escrow::at(escrow).withdraw(caller).call(&mut context);
    }

    #[private]
    fn find_and_remove_cliff_note(escrow: AztecAddress) -> CliffVestingNote {
        let options = NoteGetterOptions::with_filter(filter_note_escrow, escrow);
        let note = self.set.pop_notes(options)[0];

        // We revert if there is no note in the filter so we can probably unwrap directly
        let unwrapped_note = note.unwrap_unchecked()

        assert(unwrapped_note.escrow == escrow, "Invalid escrow address");
        unwrapped_note
    }
}