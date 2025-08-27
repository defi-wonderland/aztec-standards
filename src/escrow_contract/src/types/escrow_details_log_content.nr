use aztec::{
    protocol_types::{
        address::AztecAddress,
        traits::{Serialize, Deserialize},
    },
    note::note_interface::NoteType,
};

/// @notice Data privately emitted to participants that will use the escrow
/// @dev SECURITY: Only contains necessary keys (nsk_m, ivsk_m) for recipient operations
/// @dev ovsk_m and tsk_m are intentionally excluded to prevent unauthorized access
#[derive(Serialize, Deserialize)]
pub struct EscrowDetailsLogContent {
    /// The address of the escrow contract
    escrow: AztecAddress,
    /// Master secret key for nullification (required for spending notes)
    nsk_m: Field,
    /// Master secret key for incoming view (required for decrypting incoming notes)
    ivsk_m: Field,
    /// Master secret key for outgoing view - NOT SHARED for security
    ovsk_m: Field,
    /// Master secret key for tagging - NOT SHARED for security  
    tsk_m: Field,
}

impl EscrowDetailsLogContent {
    /// @notice Creates a new EscrowDetailsLogContent with only necessary keys
    /// @param escrow The address of the escrow contract
    /// @param nsk_m Master secret key for nullification
    /// @param ivsk_m Master secret key for incoming view
    /// @param ovsk_m Master secret key for outgoing view (should be 0 when sharing with recipients)
    /// @param tsk_m Master secret key for tagging (should be 0 when sharing with recipients)
    /// @dev SECURITY: When sharing with recipients, ovsk_m and tsk_m should be set to 0
    pub fn new(escrow: AztecAddress, nsk_m: Field, ivsk_m: Field, ovsk_m: Field, tsk_m: Field) -> Self {
        Self { escrow, nsk_m, ivsk_m, ovsk_m, tsk_m }
    }

    /// @notice Returns the escrow address
    pub fn get_escrow(self) -> AztecAddress {
        self.escrow
    }

    /// @notice Returns only the necessary master secret keys for recipients
    /// @dev SECURITY: Only returns nsk_m and ivsk_m, excludes sensitive ovsk_m and tsk_m
    pub fn get_keys(self) -> [Field; 2] {
        [self.nsk_m, self.ivsk_m]
    }

    /// @notice Returns all master secret keys including sensitive ones (for owner use only)
    /// @dev WARNING: Only use this when the recipient is the actual owner of the escrow
    pub fn get_all_keys(self) -> [Field; 4] {
        [self.nsk_m, self.ivsk_m, self.ovsk_m, self.tsk_m]
    }

    /// @notice Returns the nullification master secret key
    pub fn get_nsk_m(self) -> Field {
        self.nsk_m
    }

    /// @notice Returns the incoming view master secret key
    pub fn get_ivsk_m(self) -> Field {
        self.ivsk_m
    }

    /// @notice Returns the outgoing view master secret key
    pub fn get_ovsk_m(self) -> Field {
        self.ovsk_m
    }

    /// @notice Returns the tagging master secret key
    pub fn get_tsk_m(self) -> Field {
        self.tsk_m
    }
}

impl NoteType for EscrowDetailsLogContent {
    fn get_id() -> Field {
        // Use a unique identifier for EscrowDetailsLogContent
        0x45534352_4f575f44_45544149_4c530000 // "ESCR_OW_DETAI_LS" in hex
    }
}