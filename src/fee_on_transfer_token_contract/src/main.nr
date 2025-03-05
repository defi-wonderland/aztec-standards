mod test;

use dep::aztec::macros::aztec;
use token::macros::token;

#[token]
#[aztec]
pub contract FeeOnTransferToken {

    // encryption library
    use aztec::encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note;

    // Libs
    use dep::aztec::{
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
        prelude::{AztecAddress, Map, PublicImmutable, PublicMutable, SharedMutable},
        protocol_types::traits::Serialize,
    };

    use token::{
        auth_utils::AuthLib,
        token_utils::TokenLib::{self, BalanceSet, FieldCompressedString},
    };

    global UPDATE_DELAY_BLOCKS: u32 = 5;
    global FEE_PERCENTAGE_BASE: U128 = U128::from_integer(100);

    #[storage]
    pub struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<U128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<U128, Context>, Context>,
        // Fee on transfer storage
        fee_on_transfer: SharedMutable<U128, UPDATE_DELAY_BLOCKS, Context>,
        // Local logic storage
        owner: PublicImmutable<AztecAddress, Context>,
    }

    #[public]
    #[initializer]
    fn constructor(name: str<31>, symbol: str<31>, decimals: u8, owner: AztecAddress) {
        storage.owner.initialize(owner);
        TokenLib::token_constructor(
            storage.name,
            storage.symbol,
            storage.decimals,
            name,
            symbol,
            decimals,
        );
    }

    mod PreTransferLib {
        use super::FEE_PERCENTAGE_BASE;
        use aztec::{
            context::{PrivateContext, PublicContext},
            encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note,
            prelude::AztecAddress,
        };
        use token::token_utils::TokenLib;

        /** ==========================================================
         * ========================= FEE LOGIC =======================
         * ======================================================== */

        pub fn before_private_transfer(
            context: &mut PrivateContext,
            storage: super::Storage<&mut PrivateContext>,
            from: AztecAddress,
            _to: AztecAddress,
            amount: U128,
        ) -> U128 {
            let fee = storage.fee_on_transfer.get_current_value();
            let fee_amount = amount * fee / FEE_PERCENTAGE_BASE;
            let owner = storage.owner.read();
            TokenLib::increase_private_balance(storage.private_balances, owner, fee_amount).emit(
                encode_and_encrypt_note(context, owner, from),
            );
            amount - fee_amount
        }

        pub fn before_public_transfer(
            _context: &mut PublicContext,
            storage: super::Storage<&mut PublicContext>,
            _from: AztecAddress,
            _to: AztecAddress,
            amount: U128,
        ) -> U128 {
            let fee = storage.fee_on_transfer.get_current_value();
            let fee_amount = amount * fee / FEE_PERCENTAGE_BASE;
            let owner = storage.owner.read();
            TokenLib::increase_public_balance(storage.public_balances, owner, fee_amount);
            amount - fee_amount
        }
    }

    #[public]
    fn set_fee_on_transfer(amount: U128) {
        assert(context.msg_sender() == storage.owner.read(), "Not owner");
        assert(amount <= FEE_PERCENTAGE_BASE, "Fee cannot be greater than 100%");
        storage.fee_on_transfer.schedule_value_change(amount);
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    // TODO(#32): unconstrained fns cannot be injected in macros
    pub(crate) unconstrained fn balance_of_private(owner: AztecAddress) -> pub U128 {
        storage.private_balances.at(owner).balance_of()
    }
}

