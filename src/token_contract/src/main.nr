mod types;
mod test;

use crate::types::token_utils::token;
use dep::aztec::macros::aztec;

#[token]
#[aztec]
pub contract Token {

    use dep::compressed_string::FieldCompressedString;
    use dep::std::ops::{Add, Sub};

    use dep::aztec::{
        encrypted_logs::log_assembly_strategies::default_aes128::note::encode_and_encrypt_note,
        macros::{functions::{initializer, internal, private, public, view}, storage::storage},
        prelude::{AztecAddress, Map, PublicImmutable, PublicMutable},
        protocol_types::{point::Point, traits::{Hash, Serialize}},
    };

    // TODO: move authwit to token_utils ?
    use dep::authwit::auth::assert_current_call_valid_authwit_public;

    use crate::types::balance_set::BalanceSet;
    use crate::types::token_utils::TokenLib;

    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

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
}
