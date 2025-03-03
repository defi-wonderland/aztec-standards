mod types;

use dep::aztec::macros::aztec;

// Minimal authorization token implementation that supports `AuthWit` accounts.
// Transfers have an accumulated transfer cap set by the owner.
// The owner can add and remove addresses from the whitelist at any time.
// The auth message follows a similar pattern to the cross-chain message and includes a designated caller.
// The designated caller is ALWAYS used here, and not based on a flag as cross-chain.
// message hash = H([caller, contract, selector, ...args])
// To be read as `caller` calls function at `contract` defined by `selector` with `args`
// Including a nonce in the message hash ensures that the message can only be used once.
#[aztec]
pub contract PrivateTransferCapToken {

    use crate::types::transfer_accumulator_note::TransferAccumulatorNote;

    // Libs
    use dep::aztec::{
        context::PrivateContext,
        macros::{functions::{initializer, internal, private, public}, storage::storage},
        prelude::{AztecAddress, Map, PrivateMutable, PublicMutable, SharedMutable},
        protocol_types::traits::Serialize,
    };

    global PRIVATE_TRANSFER_CAP_DELAY_BLOCKS: u32 = 5;

    #[storage]
    struct Storage<Context> {
        owner: PublicMutable<AztecAddress, Context>,
        private_transfer_cap: SharedMutable<U128, PRIVATE_TRANSFER_CAP_DELAY_BLOCKS, Context>,
        transfer_accumulator_map: Map<AztecAddress, PrivateMutable<TransferAccumulatorNote, Context>, Context>,
    }

    #[public]
    #[initializer]
    fn constructor(
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        owner: AztecAddress,
        private_transfer_cap: U128,
    ) {
        storage.owner.write(owner);
        storage.private_transfer_cap.schedule_value_change(private_transfer_cap);
    }

    /** ==========================================================
     * ========================= PRIVATE =========================
     * ======================================================== */

    #[private]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        _authorize_in_private(from, amount, storage);
        // ...
    }

    #[private]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        _authorize_in_private(from, amount, storage);
        // ...
    }

    // Transfers token `amount` from public balance of message sender to a private balance of `to`.
    #[private]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        _authorize_in_private(from, amount, storage);
        // ...
    }
    /// Prepares an increase of private balance of `to` (partial note). The increase needs to be finalized by calling
    /// some of the finalization functions (`finalize_transfer_public_to_private`, `finalize_mint_to_private`).
    /// Returns a hiding point slot.
    #[private]
    fn prepare_transfer_public_to_private(from: AztecAddress, to: AztecAddress) -> Field {
        // ...
        // TODO: We don't have the amount here, so we can't authorize
        //_authorize_in_private(from, amount, storage);
        // ...
        0
    }

    /** ==========================================================
     * ========================= PUBLIC ==========================
     * ======================================================== */

    // #[public]
    // fn set_private_transfer_cap(private_transfer_cap: U128) {
    //     assert_eq(storage.owner.read(), context.msg_sender(), "caller is not owner");
    //     storage.private_transfer_cap.schedule_value_change(private_transfer_cap);
    // }

    #[public]
    fn transfer_public_to_public(from: AztecAddress, to: AztecAddress, amount: U128, nonce: Field) {
        // ...
    }

    /// Finalizes a transfer of token `amount` from public balance of `from` to a private balance of `to`.
    /// The transfer must be prepared by calling `prepare_transfer_public_to_private` first and the resulting
    /// `hiding_point_slot` must be passed as an argument to this function.
    #[public]
    fn finalize_transfer_public_to_private(
        from: AztecAddress,
        amount: U128,
        hiding_point_slot: Field,
        nonce: Field,
    ) {
        // ...
    }

    /// This is a wrapper around `_finalize_transfer_public_to_private` placed here so that a call
    /// to `_finalize_transfer_public_to_private` can be enqueued. Called unsafe as it does not check `from` (this has to be
    /// done in the calling function).
    #[public]
    #[internal]
    fn _finalize_transfer_public_to_private_unsafe(
        from: AztecAddress,
        amount: U128,
        hiding_point_slot: Field,
    ) {
        // ...
    }

    /** ==========================================================
     * ======================= AUTHORIZATION =====================
     * ======================================================== */

    #[contract_library_method]
    fn _authorize_in_private(
        from: AztecAddress,
        amount: U128,
        storage: Storage<&mut PrivateContext>,
    ) {
        let note = _find_transfer_accumulator_note(storage, from);

        let transfer_accumulator = note.accumulated + amount;
        assert(
            transfer_accumulator <= storage.private_transfer_cap.get_current_value(),
            "Transfer amount exceeds private transfer cap",
        );

        let mut new_note =
            TransferAccumulatorNote::new(from, transfer_accumulator, note.nonce.add(U128::one()));
        storage.transfer_accumulator_map.at(from).replace(&mut new_note);
    }

    /** ==========================================================
    * ======================= LIBRARIES =========================
    * ======================================================== */

    #[contract_library_method]
    fn _find_transfer_accumulator_note(
        storage: Storage<&mut PrivateContext>,
        from: AztecAddress,
    ) -> TransferAccumulatorNote {
        // get_note nullifies the note
        // what happens if the private mutable was not initialized?
        let note = storage.transfer_accumulator_map.at(from).get_note().note;
        // If there is no note, we return an empty one
        if note.nonce == U128::zero() {
            // Push nullifier for empty note??
            // How do we know if they are not providing the note?
            TransferAccumulatorNote::new(from, U128::zero(), U128::zero())
        } else {
            note
        }
    }
}

