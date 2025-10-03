use aztec::{
    event::{event_interface::EventInterface, event_selector::EventSelector},
    prelude::AztecAddress,
    protocol_types::traits::{Serialize, ToField},
};

/// @notice Master secret keys
/// @dev These keys are used to derive the public keys for the escrow contract
/// @param nsk_m Master Nullifier Secret Key
/// @param ivsk_m Incoming Viewing Key
/// @param ovsk_m Outgoing Viewing Key
/// @param tsk_m Tagging Secret Key
pub struct MasterSecretKeys {
    pub nsk_m: Field,
    pub ivsk_m: Field,
    pub ovsk_m: Field,
    pub tsk_m: Field,
}

impl Serialize<4> for MasterSecretKeys {
    fn serialize(self) -> [Field; 4] {
        [self.nsk_m, self.ivsk_m, self.ovsk_m, self.tsk_m]
    }
}

/// @notice Escrow details log content
/// @dev #[event] macro cannot be used in libraries, only in contracts.
/// @param escrow The address of the escrow
/// @param master_secret_keys The master secret keys
pub struct EscrowDetailsLogContent {
    pub escrow: AztecAddress,
    pub master_secret_keys: MasterSecretKeys,
}

impl Serialize<5> for EscrowDetailsLogContent {
    fn serialize(self) -> [Field; 5] {
        [
            self.escrow.to_field(),
            self.master_secret_keys.nsk_m,
            self.master_secret_keys.ivsk_m,
            self.master_secret_keys.ovsk_m,
            self.master_secret_keys.tsk_m,
        ]
    }
}

impl EventInterface for EscrowDetailsLogContent {
    fn get_event_type_id() -> EventSelector {
        EventSelector::from_signature("EscrowDetailsLogContent((Field),(Field,Field,Field,Field))")
    }
}
