use dep::aztec::macros::aztec;
mod test;
mod types;

#[aztec]
// Sample escrow contract that stores a balance of a private token on behalf of an owner.
pub contract Escrow {
    use dep::aztec::{
        encrypted_logs::log_assembly_strategies::default_aes128::{
            event::encode_and_encrypt_event, note::encode_and_encrypt_note,
        },
        keys::getters::get_public_keys,
        macros::{events::event, functions::{initializer, private}, storage::storage},
        prelude::{AztecAddress, PrivateImmutable},
        protocol_types::traits::{Hash, Serialize},
    };

    use dep::token::Token;
    use std::meta::derive;

    use crate::types::account_note::AccountNote;

    #[derive(Serialize)]
    #[event]
    struct PrivacyKeys {
        // TODO: fetch and add encryption_keys to event
        // encryption_keys: Field,
        nullification_keys: Field,
    }

    #[storage]
    struct Storage<Context> {
        owner: PrivateImmutable<AccountNote, Context>,
    }

    // Creates a new instance of the escrow contract
    #[private]
    #[initializer]
    fn constructor(owner: AztecAddress, secret: Field) {
        let mut note = AccountNote::new(owner, secret);
        let note_emission = storage.owner.initialize(&mut note);
        let self_address = context.this_address();
        note_emission.emit(encode_and_encrypt_note(&mut context, self_address, self_address));
    }

    /** ==========================================================
     * ======================= PRIVATE ===========================
     * ======================================================== */

    // Leaks privacy keys of this contract to a recipient
    #[private]
    fn leak_keys(to: AztecAddress) {
        let sender = context.msg_sender();
        let note = storage.owner.get_note();
        assert(note.owner == sender, "Unauthorized");
        let owner_npk_m_hash = get_public_keys(context.this_address()).npk_m.hash();
        let nullification_secret = context.request_nsk_app(owner_npk_m_hash);

        let leak_event = PrivacyKeys {
            // encryption_keys: encryption_secret,
            nullification_keys: nullification_secret,
        };

        leak_event.emit(encode_and_encrypt_event(&mut context, to, context.this_address()));
    }

    // Withdraws balance. Requires that msg.sender is the owner
    #[private]
    fn withdraw(token: AztecAddress, amount: U128, recipient: AztecAddress) {
        let sender = context.msg_sender();

        let note = storage.owner.get_note();
        assert(note.owner == sender, "Unauthorized");
        Token::at(token)
            .transfer_private_to_private(context.this_address(), recipient, amount, 0)
            .call(&mut context);
    }

}
