use dep::std::option::Option;

// Import only what we need
use aztec::{
    context::PrivateContext,
    encrypted_logs::log_assembly_strategies::default_aes128::note::compute_note_log,
    encrypted_logs::log_assembly_strategies::default_aes128::note::assert_note_exists,
    macros::functions::{
        abi_export::create_fn_abi_export, call_interface_stubs::stub_fn, stub_registry,
    },
    note::{note_emission::NoteEmission, note_interface::NoteType},
    oracle::capsules::{store, load},
    protocol_types::{abis::note_hash::NoteHash, address::AztecAddress, traits::Packable},
};
use aztec::encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note;
use compressed_string::FieldCompressedString;

pub fn emit_or_store_in_capsule<Note, let N: u32>(
    context: &mut PrivateContext,
    recipient: AztecAddress,
    sender: AztecAddress,
) -> fn[(&mut PrivateContext, AztecAddress, AztecAddress)](NoteEmission<Note>) -> ()
where
    Note: NoteType + Packable<N>,
{
    let storage_slot_string: str<31> = "no_emit________________________";
    let storage_slot_capsule: Field = FieldCompressedString::from_string(storage_slot_string).value;

    let no_emit = unsafe { load(context.this_address(), storage_slot_capsule).unwrap_or(false) as bool };
    if (no_emit) {
        store_in_capsule(context, recipient, sender)
    } else {
        encode_and_encrypt_note(context, recipient, sender)
    }
}

pub fn store_in_capsule<Note, let N: u32>(
    context: &mut PrivateContext,
    recipient: AztecAddress,
    sender: AztecAddress,
) -> fn[(&mut PrivateContext, AztecAddress, AztecAddress)](NoteEmission<Note>) -> ()
where
    Note: NoteType + Packable<N>,
{
    |e: NoteEmission<Note>| {
        let note = e.note;
        let storage_slot = e.storage_slot;
        let note_hash_counter = e.note_hash_counter;
        assert_note_exists(*context, note_hash_counter);

        // These two checks are added to use the recipient and sender variable. If not,
        // the function can't compile because it removes them as unused parameters.
        assert(recipient != AztecAddress::zero(), "Recipient cannot be the zero address");
        assert(sender != AztecAddress::zero(), "Sender cannot be the zero address");

        let encrypted_log = compute_note_log(note, storage_slot, recipient, sender);
        // Storage slot as an example. It should use CapsuleArray to store the notes.
        unsafe { store(context.this_address(), 66666667777888, encrypted_log) };
    }
}