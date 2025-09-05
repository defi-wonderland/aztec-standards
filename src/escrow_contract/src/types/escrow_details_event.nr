use aztec::{
    event::{event_interface::EventInterface, event_selector::EventSelector},
    prelude::AztecAddress,
    protocol_types::traits::{FromField, Serialize, ToField},
};

// #[event] macro cannot be used in libraries, only in contracts.
pub struct EscrowDetailsLogContent {
    escrow: AztecAddress,
    nsk_m: Field,
    ivsk_m: Field,
    ovsk_m: Field,
    tsk_m: Field,
}

impl Serialize<5> for EscrowDetailsLogContent {
    fn serialize(self) -> [Field; 5] {
        [self.escrow.to_field(), self.nsk_m, self.ivsk_m, self.ovsk_m, self.tsk_m]
    }
}

impl EventInterface for EscrowDetailsLogContent {
    fn get_event_type_id() -> EventSelector {
        EventSelector::from_signature("EscrowDetailsLogContent((Field),Field,Field,Field,Field)")
    }
}
