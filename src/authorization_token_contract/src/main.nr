mod types;

use dep::aztec::macros::aztec;

// Minimal authorization token implementation that supports `AuthWit` accounts.
// The auth message follows a similar pattern to the cross-chain message and includes a designated caller.
// The designated caller is ALWAYS used here, and not based on a flag as cross-chain.
// message hash = H([caller, contract, selector, ...args])
// To be read as `caller` calls function at `contract` defined by `selector` with `args`
// Including a nonce in the message hash ensures that the message can only be used once.
#[aztec]
pub contract AuthorizationToken {
    // Libs
    use dep::aztec::{
        context::{PrivateContext},
        macros::{functions::{initializer, internal, private, public}, storage::storage},
        prelude::{AztecAddress, PublicContext, SharedMutable},
        protocol_types::{traits::Serialize},
    };

    use dep::uint_note::uint_note::UintNote;


    use dep::merkle_inclussion_authorizer_contract::MerkleInclussionAuthorizer;

    // Authorizing a new address has a certain block delay before it goes into effect.
    global CHANGE_AUTHORIZED_DELAY_BLOCKS: u32 = 5;

    #[storage]
    struct Storage<Context> {
        authorizer: SharedMutable<AztecAddress, CHANGE_AUTHORIZED_DELAY_BLOCKS, Context>,
    }

    #[public]
    #[initializer]
    fn constructor(name: str<31>, symbol: str<31>, decimals: u8, authorizer: AztecAddress) {
        storage.authorizer.schedule_value_change(authorizer)
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
        _authorize_in_private(from, to, amount, &mut context, storage);
        // ...
    }

    #[private]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        nonce: Field,
    ) {
        _authorize_in_private(from, to, amount, &mut context, storage);
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
        _authorize_in_private(from, to, amount, &mut context, storage);
        // ...
    }
    /// Prepares an increase of private balance of `to` (partial note). The increase needs to be finalized by calling
    /// some of the finalization functions (`finalize_transfer_public_to_private`, `finalize_mint_to_private`).
    /// Returns a hiding point slot.
    #[private]
    fn prepare_transfer_public_to_private(to: AztecAddress, from: AztecAddress) -> Field {
        // ...
    }

    /** ==========================================================
     * ========================= PUBLIC ==========================
     * ======================================================== */

    #[public]
    fn transfer_public_to_public(from: AztecAddress, to: AztecAddress, amount: U128, nonce: Field) {
        // ...
        authorize_in_public(from, to, amount);
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

    #[public]
    fn authorize_in_public(from: AztecAddress, to: AztecAddress, amount: U128) {
        // TODO: External calls are incredibly expensive. In future versions, we should avoid making
        // external calls and add authorization logic directly to thet token contract.
        let authorizer = storage.authorizer.get_current_value();
        let authorizer_contract = MerkleInclussionAuthorizer::at(authorizer);
        authorizer_contract.authorize_in_public(from, to, amount).call(&mut context);
    }

    #[contract_library_method]
    fn _authorize_in_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
        context: &mut PrivateContext,
        storage: Storage<&mut PrivateContext>,
    ) {
        // TODO: External calls are incredibly expensive. In future versions, we should avoid making
        // external calls and add authorization logic directly to thet token contract.
        let authorizer = storage.authorizer.get_current_value();
        let authorizer_contract = MerkleInclussionAuthorizer::at(authorizer);
        authorizer_contract.authorize_in_private(from, to, amount).call(context);
    }
}

