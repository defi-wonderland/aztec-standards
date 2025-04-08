use dep::std::option::Option;

// Import only what we need
use aztec::{
    context::PrivateContext,
    encrypted_logs::log_assembly_strategies::default_aes128::note::compute_note_log,
    macros::functions::{
        abi_export::create_fn_abi_export, call_interface_stubs::stub_fn, stub_registry,
    },
    note::{note_emission::NoteEmission, note_interface::NoteType},
    oracle::capsules,
    protocol_types::{abis::note_hash::NoteHash, address::AztecAddress, traits::Packable},
};
use aztec::encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note;
use compressed_string::FieldCompressedString;

comptime fn duplicate_with_emit_to_capsule(f: FunctionDefinition) -> Quoted {
    let original_name = f.name();
    let new_name = f"{original_name}_emit_to_capsule".quoted_contents();
    let body = f.body();
    quote {
        #[private]
        fn $new_name() {$body}
    }
}

pub fn emit_or_store_in_capsule<Note, let N: u32>(
    context: &mut PrivateContext,
    recipient: AztecAddress,
    sender: AztecAddress,
) -> fn[(&mut PrivateContext, AztecAddress, AztecAddress)](NoteEmission<Note>) -> ()
where
    Note: NoteType + Packable<N>,
{
    let storage_slot_string: str<31> = "no_emit________________________";
    let storage_slot = FieldCompressedString::from_string(storage_slot_string).value;
    let no_emit = unsafe { capsules::load(context.this_address(), 1231534237488).unwrap_or(false) as bool };
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
        unsafe { capsules::store(context.this_address(), storage_slot, encrypted_log) };
    }
}

// TODO: it feels like this existence check is in the wrong place. In fact, why is it needed at all? Under what circumstances have we found a non-existent note being emitted accidentally?
fn assert_note_exists<let N: u32>(context: PrivateContext, note_hash_counter: u32) {
    // TODO(#8589): use typesystem to skip this check when not needed
    let note_exists =
        context.note_hashes.storage().any(|n: NoteHash| n.counter == note_hash_counter);
    assert(note_exists, "Can only emit a note log for an existing note.");
}
