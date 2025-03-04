mod types;
mod test;

use dep::aztec::macros::aztec;
use token::macros::token;

// Authorization token where private transfers have an accumulated transfer cap set by the owner.
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
        // transfer_accumulator_set: Set<AztecAddress, Context>,
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

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    // TODO(#32): unconstrained fns cannot be injected in macros
    pub(crate) unconstrained fn balance_of_private(owner: AztecAddress) -> pub U128 {
        storage.private_balances.at(owner).balance_of()
    }

    mod HookLib {
        use crate::types::transfer_accumulator_note::TransferAccumulatorNote;
        use aztec::{
            context::{PrivateContext, PublicContext},
            keys::getters::get_public_keys,
            oracle::notes::check_nullifier_exists,
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

            // This leaks privacy when initializing as we are connecting an address (from) with the initialization of the note
            // Outside players would know that an address interacted with a token privately the first time
            storage.transfer_accumulator_map.at(from).initialize_or_replace(&mut new_note).emit(
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
            let priv_mutable = transfer_accumulator_map.at(from);
            // This is safe as we push a nullifier if the note is not initialized
            // In case there is a malicious oracle, the nullifier would collide and revert
            let is_initialized = _unsafe_is_note_initialized(priv_mutable);
            // If there is no note, we return an empty one
            if !is_initialized {
                // Push nullifier to make sure that the oracle provides the note if it exists
                _push_first_transfer_nullifier(context, from);
                TransferAccumulatorNote::new(from, U128::zero(), U128::zero())
            } else {
                // get_note nullifies the note
                let note = priv_mutable.get_note().note;
                note
            }
        }

        fn _unsafe_is_note_initialized(
            priv_mutable: PrivateMutable<TransferAccumulatorNote, &mut PrivateContext>,
        ) -> bool {
            let is_initialized =
                unsafe { check_nullifier_exists(priv_mutable.compute_initialization_nullifier()) };
            is_initialized
        }

        fn _push_first_transfer_nullifier(context: &mut PrivateContext, from: AztecAddress) {
            let owner_npk_m_hash = get_public_keys(from).npk_m.hash();
            let secret = context.request_nsk_app(owner_npk_m_hash);
            context.push_nullifier(secret);
        }
    }
}

