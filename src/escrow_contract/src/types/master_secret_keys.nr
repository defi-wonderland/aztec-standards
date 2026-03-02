use aztec::protocol::traits::Serialize;

/// @notice Master secret keys derived from a single secret key
/// @dev These keys are used to derive the public keys for the escrow contract
/// @param nhk_m Master Nullifier Hiding Key
/// @param ivsk_m Incoming Viewing Key
/// @param ovsk_m Outgoing Viewing Key
/// @param tsk_m Tagging Secret Key
#[derive(Serialize)]
pub struct MasterSecretKeys {
    pub nhk_m: Field,
    pub ivsk_m: Field,
    pub ovsk_m: Field,
    pub tsk_m: Field,
}
