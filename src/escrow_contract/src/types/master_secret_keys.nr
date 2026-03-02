use std::embedded_curve_ops::EmbeddedCurveScalar;

/// @notice Master secret keys derived from a single secret key
/// @dev These keys are used to derive the public keys for the escrow contract
/// @param nhk_m Master Nullifier Hiding Key
/// @param ivsk_m Incoming Viewing Key
/// @param ovsk_m Outgoing Viewing Key
/// @param tsk_m Tagging Secret Key
pub struct MasterSecretKeys {
    pub nhk_m: EmbeddedCurveScalar,
    pub ivsk_m: EmbeddedCurveScalar,
    pub ovsk_m: EmbeddedCurveScalar,
    pub tsk_m: EmbeddedCurveScalar,
}
