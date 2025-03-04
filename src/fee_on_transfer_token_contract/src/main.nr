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

    use balance_set::balance_set::BalanceSet;

    use token::{auth_utils::AuthLib, token_utils::TokenLib};

    global UPDATE_DELAY_BLOCKS: u32 = 5;
    global FEE_PERCENTAGE_BASE: U128 = U128::from_integer(100);

    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<TokenLib::FieldCompressedString, Context>,
        symbol: PublicImmutable<TokenLib::FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<U128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<U128, Context>, Context>,
        // Private transfer cap
        owner: SharedMutable<AztecAddress, UPDATE_DELAY_BLOCKS, Context>,
        fee_on_transfer: SharedMutable<U128, UPDATE_DELAY_BLOCKS, Context>,
    }

    #[public]
    #[initializer]
    fn constructor(name: str<31>, symbol: str<31>, decimals: u8, owner: AztecAddress) {
        storage.owner.schedule_value_change(owner);
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
        use super::FEE_PERCENTAGE_BASE;
        use aztec::{context::{PrivateContext, PublicContext}, prelude::AztecAddress};
        use aztec::encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note;
        use token::token_utils::TokenLib;

        /** ==========================================================
         * ========================= FEE LOGIC =======================
         * ======================================================== */

        fn before_private_transfer(
            context: &mut PrivateContext,
            storage: super::Storage<&mut PrivateContext>,
            _from: AztecAddress,
            _to: AztecAddress,
            amount: U128,
        ) -> U128 {
            let fee = storage.fee_on_transfer.get_current_value();
            let fee_amount = amount * fee / FEE_PERCENTAGE_BASE;
            let owner = storage.owner.get_current_value();
            TokenLib::_increase_private_balance(storage.private_balances, owner, fee_amount).emit(
                encode_and_encrypt_note(context, owner, _from),
            );
            amount - fee_amount
        }

        fn before_public_transfer(
            _context: &mut PublicContext,
            storage: super::Storage<&mut PublicContext>,
            _from: AztecAddress,
            _to: AztecAddress,
            amount: U128,
        ) -> U128 {
            let fee = storage.fee_on_transfer.get_current_value();
            let fee_amount = amount * fee / FEE_PERCENTAGE_BASE;
            let owner = storage.owner.get_current_value();
            TokenLib::_increase_public_balance(storage.public_balances, owner, fee_amount);
            amount - fee_amount
        }
    }

    #[public]
    fn set_fee_on_transfer(amount: U128) {
        assert(context.msg_sender() == storage.owner.get_current_value(), "Not owner");
        assert(amount <= FEE_PERCENTAGE_BASE, "Fee cannot be greater than 100%");
        storage.fee_on_transfer.schedule_value_change(amount);
    }
}

