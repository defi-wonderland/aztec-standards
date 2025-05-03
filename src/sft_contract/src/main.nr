mod types;
mod test;

use aztec::macros::aztec;

#[aztec]
pub contract SFT {
    // Import necessary modules and types
    use crate::types::sft_note::{SFTNote, PartialSFTNote}; // We'll need to create these types
    
    // aztec library imports
    use aztec::{
        context::PrivateContext,
        macros::{
            functions::{initializer, internal, private, public, utility, view},
            storage::storage,
        },
        messages::logs::note::encode_and_encrypt_note,
        note::{constants::MAX_NOTES_PER_PAGE, note_interface::NoteProperties},
        prelude::{
            AztecAddress, Map, NoteGetterOptions, NoteViewerOptions, 
            PrivateSet, PublicContext, PublicImmutable, PublicMutable,
        },
        utils::comparison::Comparator,
    };
    
    // authorized witness library
    use authwit::auth::{
        assert_current_call_valid_authwit,
        assert_current_call_valid_authwit_public,
    };
    
    // compression library
    use compressed_string::FieldCompressedString;
    
    // balance library (we'll use this for tracking token amounts)
    use balance_set::balance_set::BalanceSet;

    // Constants for gas optimization (similar to Token contract)
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    /// Storage structure for the SFT contract
    /// @param name The name of the token collection
    /// @param symbol The symbol of the token collection
    /// @param uri The base URI for token metadata
    /// @param private_balances Map of (address, tokenId) to balance set for private holdings
    /// @param public_balances Map of (address, tokenId) to amount for public holdings
    /// @param token_exists Map to track which token IDs have been created
    /// @param token_supplies Map of token ID to total supply
    /// @param minter The address that can create new token types
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        uri: PublicImmutable<FieldCompressedString, Context>,
        
        // Private balances: address -> token_id -> BalanceSet
        private_balances: Map<AztecAddress, Map<Field, BalanceSet<Context>, Context>, Context>,
        
        // Public balances: address -> token_id -> amount
        public_balances: Map<AztecAddress, Map<Field, PublicMutable<u128, Context>, Context>, Context>,
        
        // Track which token IDs exist
        token_exists: Map<Field, PublicMutable<bool, Context>, Context>,
        
        // Track total supply per token ID
        token_supplies: Map<Field, PublicMutable<u128, Context>, Context>,
        
        // Minter role
        minter: PublicImmutable<AztecAddress, Context>,
    }

    // Constructor and function implementations will follow in next steps...
}
