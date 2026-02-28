use aztec::{
    event::{event_interface::EventInterface, EventSelector},
    protocol::{address::AztecAddress, traits::Serialize},
};

/// @notice Escrow details log content
/// @dev #[event] macro cannot be used in libraries, only in contracts.
/// @param escrow The address of the escrow
/// @param secret_key The secret key used to derive master secret keys and public keys
#[derive(Serialize)]
pub struct EscrowDetailsLogContent {
    pub escrow: AztecAddress,
    pub secret_key: Field,
}

impl EventInterface for EscrowDetailsLogContent {
    fn get_event_type_id() -> EventSelector {
        EventSelector::from_signature("EscrowDetailsLogContent((Field),Field)")
    }
}
