use aztec::{
    event::{event_interface::EventInterface, event_selector::EventSelector},
    protocol_types::{address::AztecAddress, traits::{Serialize, ToField}},
};

/// @notice Escrow details log content
/// @dev #[event] macro cannot be used in libraries, only in contracts.
/// @param escrow The address of the escrow
/// @param secret_key The secret key used to derive master secret keys and public keys
pub struct EscrowDetailsLogContent {
    pub escrow: AztecAddress,
    pub secret_key: Field,
}

impl Serialize for EscrowDetailsLogContent {
    let N: u32 = 2;

    fn serialize(self) -> [Field; Self::N] {
        [self.escrow.to_field(), self.secret_key]
    }
}

impl EventInterface for EscrowDetailsLogContent {
    fn get_event_type_id() -> EventSelector {
        EventSelector::from_signature("EscrowDetailsLogContent((Field),Field)")
    }
}
