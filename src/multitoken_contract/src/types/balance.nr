use crate::types::multitoken_note::MultiTokenNote;
use aztec::{
    context::{PrivateContext, UtilityContext},
    messages::delivery::MessageDelivery,
    note::{
        HintedNote,
        note_getter_options::{NoteGetterOptions, SortOrder},
        note_interface::NoteProperties,
        note_viewer_options::NoteViewerOptions,
    },
    protocol::{address::AztecAddress, constants::MAX_NOTE_HASH_READ_REQUESTS_PER_CALL},
    state_vars::{OwnedStateVariable, PrivateSet},
    utils::comparison::Comparator,
};
use std::ops::Add;

/// A per-owner set of `MultiTokenNote`s. The `MultiTokenNote` analogue of `balance_set::BalanceSet` (which is
/// `UintNote`-only): same wrapper-over-`PrivateSet` shape, but one base slot holds notes for many token ids, so every
/// op takes an `id: Field` and applies `select(token_id == id)`.
pub struct MultiBalanceSet<Context> {
    set: PrivateSet<MultiTokenNote, Context>,
}

// TODO: remove this impl once Aztec allows structs to hold state variables. Identical to `BalanceSet`'s.
impl<Context> OwnedStateVariable<Context> for MultiBalanceSet<Context> {
    fn new(context: Context, storage_slot: Field, owner: AztecAddress) -> Self {
        Self { set: PrivateSet::new(context, storage_slot, owner) }
    }
}

impl MultiBalanceSet<UtilityContext> {
    /// Total balance of `id` for the owner. Off-chain helper, unbounded cost (grows with the owner's note count).
    pub unconstrained fn balance_of(self: Self, id: Field) -> u128 {
        self.balance_of_with_offset(id, 0)
    }

    /// Sums the owner's notes for `id`, paging across the set. Filters on `token_id == id` at the oracle level so we
    /// only page through matching notes.
    pub unconstrained fn balance_of_with_offset(self: Self, id: Field, offset: u32) -> u128 {
        let mut options = NoteViewerOptions::new();
        let notes = self.set.view_notes(options.set_offset(offset).select(
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
            balance += self.balance_of_with_offset(id, offset + options.limit);
        }
        balance
    }
}

impl MultiBalanceSet<&mut PrivateContext> {
    /// Credits `amount` of `id` to the owner. A zero `amount` yields no note (a balance-neutral note would still cost a
    /// note hash + DA gas).
    pub fn add(self: Self, id: Field, amount: u128) {
        if amount != 0 {
            let note = MultiTokenNote { token_id: id, value: amount };
            self.set.insert(note).deliver(MessageDelivery::onchain_constrained());
        }
    }

    /// Pops up to `max_notes` notes of `id` in one frame, returning the total value nullified. The `select` is
    /// constrained (pop_notes proves each note's `token_id == id`) and applied before `set_limit`, so only matching
    /// notes are ever nullified.
    pub fn try_sub(self: Self, id: Field, amount: u128, max_notes: u32) -> u128 {
        let options = NoteGetterOptions::with_preprocessor(preprocess_multitoken_min_sum, amount)
            .select(MultiTokenNote::properties().token_id, Comparator.EQ, id)
            .sort(MultiTokenNote::properties().value, SortOrder.DESC)
            .set_limit(max_notes);
        let notes = self.set.pop_notes(options);

        let mut nullified = 0 as u128;
        for i in 0..options.limit {
            if i < notes.len() {
                nullified += notes.get_unchecked(i).value;
            }
        }
        nullified
    }
}

/// Keeps notes in retrieved order until their running sum reaches `min_sum`, dropping the rest, to minimize the number
/// of notes read. Runs unconstrained (just an optimization, not proven). Stays a free `fn` because `with_preprocessor`
/// takes it by name - same as `balance_set`.
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
