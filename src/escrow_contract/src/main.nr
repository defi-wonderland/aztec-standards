use dep::aztec::macros::aztec;

#[aztec]
// Sample escrow contract that stores a balance of a private token on behalf of an owner.
pub contract Escrow {
    use dep::aztec::{
        encrypted_logs::log_assembly_strategies::default_aes128::{
            event::encode_and_encrypt_event_unconstrained,
            note::{encode_and_encrypt_note, encode_and_encrypt_note_unconstrained},
        },
        keys::getters::get_public_keys,
        macros::{events::event, functions::{initializer, private}, storage::storage},
        prelude::{AztecAddress, PrivateImmutable},
        protocol_types::traits::Serialize,
    };

    use dep::address_note::address_note::AddressNote;
    use dep::token::Token;
    use std::meta::derive;

    #[derive(Serialize)]
    #[event]
    struct PrivacyKeys {
        // TODO: fetch and add encryption_keys to event
        // encryption_keys: Field,
        nullification_keys: Field,
    }

    #[storage]
    struct Storage<Context> {
        owner: PrivateImmutable<AddressNote, Context>,
    }

    // Creates a new instance
    #[private]
    #[initializer]
    fn constructor(owner: AztecAddress) {
        let mut note = AddressNote::new(owner, owner);
        storage.owner.initialize(&mut note).emit(encode_and_encrypt_note_unconstrained(
            &mut context,
            // NOTE: assuming non-factory deployment (msg_sender = Alice)
            // TODO: encrypt for Alice
            owner, // to: Bob
            context.this_address(), // from: Escrow
        ));
    }

    // Leaks privacy keys of this contract to a recipient
    #[private]
    fn leak_keys(to: AztecAddress) {
        let sender = context.msg_sender();
        let note = storage.owner.get_note();
        assert(note.address == sender);
        // TODO: refactor AddressNote to fulfill our needs

        let owner_npk_m_hash: Field = get_public_keys(context.this_address()).npk_m.hash();
        let nullification_secret = context.request_nsk_app(owner_npk_m_hash);

        PrivacyKeys {
            // encryption_keys: encryption_secret,
            nullification_keys: nullification_secret,
        }
            .emit(encode_and_encrypt_event_unconstrained(&mut context, to, context.this_address()))
    }

    // Withdraws balance. Requires that msg.sender is the owner
    #[private]
    fn withdraw(token: AztecAddress, amount: U128, recipient: AztecAddress) {
        let sender = context.msg_sender();

        let note = storage.owner.get_note();
        assert(note.address == sender);
        Token::at(token)
            .transfer_private_to_private(context.this_address(), recipient, amount, 0)
            .call(&mut context);
    }
}
