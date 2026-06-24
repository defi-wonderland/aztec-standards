use crate::types::multitoken_note::MultiTokenNote;
use aztec::{
    context::{PrivateContext, UtilityContext},
    messages::message_delivery::MessageDelivery,
    note::{HintedNote, note_interface::NoteProperties, note_viewer_options::NoteViewerOptions},
    protocol::constants::MAX_NOTE_HASH_READ_REQUESTS_PER_CALL,
    state_vars::PrivateSet,
    utils::comparison::Comparator,
};
use std::ops::Add;

/// Computes the partial sum of the notes array, stopping once `min_sum` is reached. This is used to minimize the number
/// of notes read that add up to some value, e.g. when transferring some amount of tokens. The preprocessor (a filter
/// applied in an unconstrained context) does not check if the total sum is larger than or equal to `min_sum` - all it
/// does is remove extra notes once it does reach that value. Note that proper usage of this preprocessor requires for
/// notes to be sorted in descending order.
///
/// This is a re-expression of `balance_set::preprocess_notes_min_sum` (which is hardcoded to `UintNote`) over
/// `MultiTokenNote`, reading the note's `value` field. We do not depend on `balance_set` because its `BalanceSet` type
/// is `UintNote`-only.
pub fn preprocess_multitoken_min_sum(
    notes: [Option<HintedNote<MultiTokenNote>>; MAX_NOTE_HASH_READ_REQUESTS_PER_CALL],
    min_sum: u128,
) -> [Option<HintedNote<MultiTokenNote>>; MAX_NOTE_HASH_READ_REQUESTS_PER_CALL] {
    let mut selected = [Option::none(); MAX_NOTE_HASH_READ_REQUESTS_PER_CALL];
    let mut sum = 0 as u128;
    for i in 0..notes.len() {
        // Because we process notes in retrieved order, notes need to be sorted in descending amount order for this
        // filter to be useful. Consider a `min_sum` of 4, and a set of notes with amounts [3, 2, 1, 1, 1, 1, 1]. If
        // sorted in descending order, the filter will only choose the notes with values 3 and 2, but if sorted in
        // ascending order it will choose 4 notes of value 1.
        if notes[i].is_some() & (sum < min_sum) {
            let hinted_note = notes[i].unwrap_unchecked();
            selected[i] = Option::some(hinted_note);
            sum = sum.add(hinted_note.note.value);
        }
    }
    selected
}

/// Credits `amount` of `id` to the owner of `set` by inserting a `MultiTokenNote` and delivering it on-chain.
///
/// Mirrors `balance_set::BalanceSet::add`: a zero `amount` yields no note. A zero-value note is valid and would
/// otherwise be inserted and delivered like any other one - costing a note hash plus an on-chain private log (DA gas)
/// under ONCHAIN_CONSTRAINED delivery - without ever changing the owner's balance.
pub fn add_to_id_balance(
    set: PrivateSet<MultiTokenNote, &mut PrivateContext>,
    id: Field,
    amount: u128,
) {
    if amount != 0 {
        let note = MultiTokenNote { token_id: id, value: amount };
        set.insert(note).deliver(MessageDelivery.ONCHAIN_CONSTRAINED);
    }
}

/// Sums the value of an owner's notes whose token id equals `id`, paging through the note set.
///
/// Recurses across pages, mirroring `balance_set::BalanceSet::balance_of_with_offset`, plus a per-id filter. Because
/// the set shares one slot across all token ids, we filter on `token_id == id` at the oracle level via `select`, so we
/// only page through the notes matching `id` instead of fetching every note and discarding the rest while summing.
/// This is an off-chain utility helper with no proving or on-chain cost and no fixed cap; its cost grows with the
/// owner's note count for `id`.
pub unconstrained fn balance_of_id_with_offset(
    set: PrivateSet<MultiTokenNote, UtilityContext>,
    id: Field,
    offset: u32,
) -> u128 {
    let mut options = NoteViewerOptions::new();
    let notes = set.view_notes(options.set_offset(offset).select(
        MultiTokenNote::properties().token_id,
        Comparator.EQ,
        id,
    ));
    let mut balance = 0 as u128;
    for i in 0..options.limit {
        if i < notes.len() {
            balance += notes.get_unchecked(i).value;
        }
    }
    if notes.len() == options.limit {
        balance += balance_of_id_with_offset(set, id, offset + options.limit);
    }
    balance
}
