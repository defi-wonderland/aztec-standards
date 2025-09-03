use aztec::{
    event::{event_interface::EventInterface, event_selector::EventSelector},
    prelude::AztecAddress,
    protocol_types::traits::{FromField, Serialize, ToField},
};

// #[event] macro cannot be used in libraries, only in contracts.
pub struct EscrowDetailsLogContent {
    escrow: AztecAddress,
    keys: [Field; 4],
}

impl Serialize<5> for EscrowDetailsLogContent {
    fn serialize(self) -> [Field; 5] {
        [self.escrow.to_field(), self.keys[0], self.keys[1], self.keys[2], self.keys[3]]
    }
}

impl EventInterface for EscrowDetailsLogContent {
    fn get_event_type_id() -> EventSelector {
        // From expansion of the event macro
        EventSelector::from_field(3937172520)
    }
}
