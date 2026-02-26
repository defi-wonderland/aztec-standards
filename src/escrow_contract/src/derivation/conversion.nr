use aztec::protocol::traits::Serialize;
use serde::writer::Writer;

/// @notice Master secret keys derived from a single secret key
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
        let mut writer: Writer<Self::N> = Writer::new();
        self.stream_serialize(&mut writer);
        writer.finish()
    }

    fn stream_serialize<let M: u32>(self, writer: &mut Writer<M>) {
        writer.write(self.nsk_m);
        writer.write(self.ivsk_m);
        writer.write(self.ovsk_m);
        writer.write(self.tsk_m);
    }
}
