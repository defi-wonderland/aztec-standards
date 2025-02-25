mod test;
mod token;
mod types;

use token::token_utils::token;
use aztec::macros::aztec;

#[token]
#[aztec]
pub contract Token {

    use compressed_string::FieldCompressedString;

    use aztec::{
        encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note,
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
        prelude::{AztecAddress, Map, PublicImmutable, PublicMutable},
        protocol_types::{
            point::Point,
            traits::{Hash, Serialize},
        },
    };

    use crate::types::balance_set::BalanceSet;
    use crate::token::{token_utils::TokenLib, auth_utils::AuthLib};

    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        total_supply: PublicMutable<U128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<U128, Context>, Context>,
    }

    #[public]
    #[initializer]
    fn constructor(name: str<31>, symbol: str<31>, decimals: u8) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.decimals.initialize(decimals);
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    pub(crate) unconstrained fn balance_of_private(owner: AztecAddress) -> pub U128 {
        storage.private_balances.at(owner).balance_of()
    }
}
