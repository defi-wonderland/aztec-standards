mod types;

use dep::aztec::macros::aztec;
use token::macros::token;

// Minimal authorization token implementation that supports `AuthWit` accounts.
// Transfers have an accumulated transfer cap set by the owner.
// The owner can add and remove addresses from the whitelist at any time.
// The auth message follows a similar pattern to the cross-chain message and includes a designated caller.
// The designated caller is ALWAYS used here, and not based on a flag as cross-chain.
// message hash = H([caller, contract, selector, ...args])
// To be read as `caller` calls function at `contract` defined by `selector` with `args`
// Including a nonce in the message hash ensures that the message can only be used once.
#[token]
#[aztec]
pub contract PrivateTransferCapToken {
    use crate::types::transfer_accumulator_note::TransferAccumulatorNote;

    // encryption library
    // TODO: remember to add this import to the token impl for it to work
    use aztec::encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note;

    // Libs
    use dep::aztec::{
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
        prelude::{AztecAddress, Map, PrivateMutable, PublicImmutable, PublicMutable, SharedMutable},
        protocol_types::traits::Serialize,
    };

    use balance_set::balance_set::BalanceSet;

    use token::{auth_utils::AuthLib, token_utils::TokenLib};

    global PRIVATE_TRANSFER_CAP_DELAY_BLOCKS: u32 = 5;

    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<TokenLib::FieldCompressedString, Context>,
        symbol: PublicImmutable<TokenLib::FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<U128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<U128, Context>, Context>,
        // Private transfer cap
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
        TokenLib::token_constructor(
            storage.name,
            storage.symbol,
            storage.decimals,
            name,
            symbol,
            decimals,
        );
    }

    mod HookLib {
        use crate::types::transfer_accumulator_note::TransferAccumulatorNote;
        use aztec::{
            context::{PrivateContext, PublicContext},
            keys::getters::get_public_keys,
            prelude::{AztecAddress, Map, PrivateMutable},
            protocol_types::{
                constants::GENERATOR_INDEX__NOTE_NULLIFIER, hash::poseidon2_hash_with_separator,
            },
        };
        use aztec::encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note;

        /** ==========================================================
         * ======================= AUTHORIZATION =====================
         * ======================================================== */

        fn before_private_transfer(
            context: &mut PrivateContext,
            storage: super::Storage<&mut PrivateContext>,
            from: AztecAddress,
            _to: AztecAddress,
            amount: U128,
        ) {
            let note =
                _find_transfer_accumulator_note(context, storage.transfer_accumulator_map, from);

            let transfer_accumulator = note.accumulated + amount;
            assert(
                transfer_accumulator <= storage.private_transfer_cap.get_current_value(),
                "Transfer amount exceeds private transfer cap",
            );

            let mut new_note = TransferAccumulatorNote::new(
                from,
                transfer_accumulator,
                note.nonce.add(U128::one()),
            );

            storage.transfer_accumulator_map.at(from).replace(&mut new_note).emit(
                encode_and_encrypt_note(context, from, from),
            );
        }

        fn before_public_transfer(
            _context: &mut PublicContext,
            _storage: super::Storage<&mut PublicContext>,
            _from: AztecAddress,
            _to: AztecAddress,
            _amount: U128,
        ) {
            // NOTE: does nothing but is required by the token template
        }

        /** ==========================================================
        * ======================= LIBRARIES =========================
        * ======================================================== */

        fn _find_transfer_accumulator_note(
            context: &mut PrivateContext,
            transfer_accumulator_map: Map<AztecAddress, PrivateMutable<TransferAccumulatorNote, &mut PrivateContext>, &mut PrivateContext>,
            from: AztecAddress,
        ) -> TransferAccumulatorNote {
            // get_note nullifies the note
            // what happens if the private mutable was not initialized?
            let note = transfer_accumulator_map.at(from).get_note().note;
            // If there is no note, we return an empty one
            if note.nonce == U128::zero() {
                // Push nullifier for empty note??
                // How do we know if they are not providing the note?
                _push_first_transfer_nullifier(context, from);
                let mut emptyNote = TransferAccumulatorNote::new(from, U128::zero(), U128::zero());
                transfer_accumulator_map.at(from).initialize(&mut emptyNote);
                emptyNote
            } else {
                note
            }
        }

        fn _push_first_transfer_nullifier(context: &mut PrivateContext, from: AztecAddress) {
            let owner_npk_m_hash = get_public_keys(from).npk_m.hash();
            let secret = context.request_nsk_app(owner_npk_m_hash);
            context.push_nullifier(poseidon2_hash_with_separator(
                [secret, from.to_field(), U128::zero().to_field()],
                GENERATOR_INDEX__NOTE_NULLIFIER as Field,
            ));
        }
    }
}

