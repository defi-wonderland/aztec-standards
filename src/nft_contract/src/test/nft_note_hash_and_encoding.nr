use dep::aztec::{
    note::note_interface::NoteHash,
    protocol_types::{
        address::AztecAddress,
        traits::{FromField, Packable},
        utils::arrays::array_concat,
    },
    utils::array::subarray,
};

use crate::types::nft_note::{
    NFTNote, NFTPartialNotePrivateContent, PartialNFTNote,
    PrivateNFTPartialNotePrivateLogContent,
};

global token_id: Field = 17;
global randomness: Field = 42;
global owner: AztecAddress = AztecAddress::from_field(50);
global storage_slot: Field = 13;

#[test]
fn note_hash_matches_completed_partial_note_hash() {
    // Tests that a NFTNote has the same note hash as a PartialNFTNote created and then completed with the same
    // private values. This requires for the same hash function to be used in both flows, with the fields in the
    // same order.

    let note = NFTNote { token_id, randomness, owner };
    let note_hash = note.compute_note_hash(storage_slot);

    let partial_note_private_content = NFTPartialNotePrivateContent { owner, randomness };

    let partial_note = PartialNFTNote {
        commitment: partial_note_private_content.compute_partial_commitment(storage_slot),
    };
    let completed_partial_note_hash = partial_note.compute_complete_note_hash(token_id);

    assert_eq(note_hash, completed_partial_note_hash);
}

#[test]
fn unpack_from_partial_note_encoding() {
    // Tests that the packed representation of a regular NFTNote can be reconstructed given the partial note
    // private fields log and the public completion log, ensuring the recipient will be able to compute the
    // completed note as if it were a regular NFTNote.

    let note = NFTNote { token_id, randomness, owner };

    let partial_note_private_content = NFTPartialNotePrivateContent { owner, randomness };
    let commitment = partial_note_private_content.compute_partial_commitment(storage_slot);

    let private_log_content = PrivateNFTPartialNotePrivateLogContent {
        owner,
        randomness,
        public_log_tag: commitment,
    };
    let partial_note = PartialNFTNote { commitment };

    // The first field of the partial note private content is the public completion log tag, so it should match the
    // first field of the public log.
    assert_eq(
        private_log_content.pack()[0],
        partial_note.compute_note_completion_log(token_id)[0],
    );

    // Then we exctract all fields except the first of both logs (i.e. the public log tag), and combine them to
    // produce the note's packed representation. This requires that the members of the intermediate structs are in
    // the same order as in NFTNote.
    let private_log_without_public_tag: [_; 2] = subarray(private_log_content.pack(), 1);
    let public_log_without_tag: [_; 1] =
        subarray(partial_note.compute_note_completion_log(token_id), 1);

    assert_eq(
        array_concat(private_log_without_public_tag, public_log_without_tag),
        note.pack(),
    );
}
