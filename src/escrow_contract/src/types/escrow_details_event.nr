use dep::aztec::{
    event::{event_interface::EventInterface, event_selector::EventSelector},
    protocol_types::{address::AztecAddress, traits::{Serialize, ToField}},
};

// #[event] macro cannot be used in libraries, only in contracts.
pub struct EscrowDetailsLogContent {
    pub escrow: AztecAddress,
    pub nsk_m: Field,
    pub ivsk_m: Field,
    pub ovsk_m: Field,
    pub tsk_m: Field,
}

impl Serialize for EscrowDetailsLogContent {
    let N: u32 = 5;

    fn serialize(self) -> [Field; Self::N] {
        [
            self.escrow.to_field(),
            self.nsk_m,
            self.ivsk_m,
            self.ovsk_m,
            self.tsk_m,
        ]
    }
}

impl EventInterface for EscrowDetailsLogContent {
    fn get_event_type_id() -> EventSelector {
        EventSelector::from_signature("EscrowDetailsLogContent((Field),Field,Field,Field,Field)")
    }
}
