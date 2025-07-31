mod types;

use aztec::macros::aztec;

#[aztec]
pub contract SFT {
    // aztec library
    use aztec::{
        macros::{
            functions::{initializer, public, utility, view},
            storage::storage,
        },
        prelude::{
            AztecAddress, Map, NoteViewerOptions, PrivateSet, PublicImmutable, PublicMutable,
        },
    };
    // compression library
    use compressed_string::FieldCompressedString;
    // sft note struct
    use crate::types::sft_note::SFTNote;

    /// Storage layout for Semi-Fungible Token (SFT) contract
    /// @param name The name of the SFT collection
    /// @param symbol The symbol of the SFT collection
    /// @param token_metadata Token type metadata including current_item_id and token_item_limit
    /// @param private_sfts Private SFT ownership using nested mapping (address -> token_id -> PrivateSet<SFTNote>)
    /// @param public_balances Public SFT balances using nested mapping (address -> token_id -> quantity)
    /// @param minter The account permissioned to mint new tokens (zero address if minting disabled)
    /// @param upgrade_authority The account allowed to upgrade the contract (zero address if not upgradeable)
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        current_item_id: Map<Field, PublicMutable<Field, Context>, Context>,
        token_item_limit: Map<Field, PublicMutable<Field, Context>, Context>,
        private_sfts: Map<AztecAddress, Map<Field, PrivateSet<SFTNote, Context>, Context>, Context>,
        public_balances: Map<AztecAddress, Map<Field, PublicMutable<u128, Context>, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
        upgrade_authority: PublicImmutable<AztecAddress, Context>,
    }

    /** ==========================================================
     * ===================== INITIALIZERS ========================
     * ======================================================== */

    /// @notice Initializes the SFT contract with a minter
    /// @param name The name of the SFT collection
    /// @param symbol The symbol of the SFT collection
    /// @param minter The address of the minter (zero address to disable minting)
    /// @param upgrade_authority The address of the upgrade authority (zero address if not upgradeable)
    #[public]
    #[initializer]
    fn constructor_with_minter(
        name: str<31>,
        symbol: str<31>,
        minter: AztecAddress,
        upgrade_authority: AztecAddress,
    ) {
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        storage.minter.initialize(minter);
        storage.upgrade_authority.initialize(upgrade_authority);
    }


    /// @notice Creates a new token type with specified limit
    /// @param token_id The ID of the new token type
    /// @param token_item_limit Maximum items that can be minted for this token
    #[public]
    fn create_token_type(token_id: Field, token_item_limit: Field) {
        _validate_minter(context.msg_sender(), storage.minter.read());

        let existing_limit = storage.token_item_limit.at(token_id).read();
        assert(existing_limit as u128 == 0, "Token already exists");

        storage.current_item_id.at(token_id).write(0); // Start at 0 (no items minted yet)
        storage.token_item_limit.at(token_id).write(token_item_limit);
    }

    /// @notice Returns the public balance of `owner` for `token_id`
    /// @param owner The address of the owner
    /// @param token_id The ID of the token type
    /// @return The balance of the public balance of `owner` for `token_id`
    #[public]
    #[view]
    fn balance_of_public(owner: AztecAddress, token_id: Field) -> u128 {
        storage.public_balances.at(owner).at(token_id).read()
    }

    /// @notice Returns the total supply of `token_id`
    /// @param token_id The ID of the token type
    /// @return The total supply of `token_id`
    #[public]
    #[view]
    fn total_supply(token_id: Field) -> u128 {
        let current_id = storage.current_item_id.at(token_id).read();
        current_id as u128
    }

    /// @param token_id The ID of the token type
    /// @return whether `token_id` exists
    #[public]
    #[view]
    fn token_exists(token_id: Field) -> bool {
        let limit = storage.token_item_limit.at(token_id).read();
        limit as u128 > 0
    }

    /// @param token_id The ID of the token type
    /// @return the current item ID for a token type
    #[public]
    #[view]
    fn get_current_item_id(token_id: Field) -> Field {
        storage.current_item_id.at(token_id).read()
    }

    /// @param token_id The ID of the token type
    /// @return the item limit for a token type
    #[public]
    #[view]
    fn get_token_item_limit(token_id: Field) -> Field {
        storage.token_item_limit.at(token_id).read()
    }

    /// @return the name of the SFT collection
    #[public]
    #[view]
    fn name() -> FieldCompressedString {
        storage.name.read()
    }

    /// @return the symbol of the SFT collection
    #[public]
    #[view]
    fn symbol() -> FieldCompressedString {
        storage.symbol.read()
    }

    /// @param owner The address of the owner
    /// @param token_id The ID of the token type
    /// @return the private balance of `owner` for `token_id`
    #[utility]
    pub unconstrained fn balance_of_private(owner: AztecAddress, token_id: Field) -> u128 {
        // Count the number of SFTNotes for this token_id
        let mut balance = 0 as u128;
        let options = NoteViewerOptions::new();
        let notes = storage.private_sfts.at(owner).at(token_id).view_notes(options);
        for i in 0..options.limit {
            if i < notes.len() {
                balance = balance + 1;
            }
        }
        // TODO: Implement recursive viewing if notes.len() == options.limit
        balance
    }

    /// validates that the caller is the minter
    #[utility]
    unconstrained fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }

    /// validates that the token exists
    #[utility]
    unconstrained fn _validate_token_exists(token_id: Field) {
        let limit = storage.token_item_limit.at(token_id).read();
        assert(limit as u128 > 0, "token does not exist");
    }

    /// validates that minting does not exceed token limit
    #[utility]
    unconstrained fn _validate_mint_limit(token_id: Field, quantity: u128) {
        let current_id = storage.current_item_id.at(token_id).read();
        let limit = storage.token_item_limit.at(token_id).read();
        assert(
            (current_id as u128) + (quantity as u128) <= (limit as u128),
            "exceeds token limit",
        );
    }
}
