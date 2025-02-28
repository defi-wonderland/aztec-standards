mod test;
mod token;

use aztec::macros::aztec;
use token::macros::token;

#[token]
#[aztec]
pub contract Token {

    use aztec::{
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
        prelude::{AztecAddress, Map, PublicImmutable, PublicMutable},
        protocol_types::traits::{Hash, Serialize},
    };

    // encryption library
    use aztec::encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note;
    // balance notes library (NOTE: it needs to be same as in the token_utils.nr)
    use balance_set::balance_set::BalanceSet;
    // token & auth utils (TODO(#30): +mint-auth utils)
    use crate::token::{auth_utils::AuthLib, token_utils::TokenLib};

    #[storage]
    struct Storage<Context> {
        // TODO: fix "is private and not visible from the current module" warning
        // TODO: why BalanceSet cannot be imported from TokenLib while FieldCompressedString can?
        name: PublicImmutable<TokenLib::FieldCompressedString, Context>,
        symbol: PublicImmutable<TokenLib::FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<U128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<U128, Context>, Context>,
    }

    #[public]
    #[initializer]
    fn constructor(name: str<31>, symbol: str<31>, decimals: u8) {
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
}
