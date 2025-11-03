use aztec::{
    event::{event_interface::EventInterface, event_selector::EventSelector},
    protocol_types::{address::AztecAddress, traits::{Serialize, ToField}},
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

impl Serialize for MasterSecretKeys {
    let N: u32 = 4;

    fn serialize(self) -> [Field; Self::N] {
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

impl Serialize for EscrowDetailsLogContent {
    let N: u32 = 5;

    fn serialize(self) -> [Field; Self::N] {
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
