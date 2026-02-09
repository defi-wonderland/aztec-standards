use aztec::protocol::public_keys::{IvpkM, NpkM, OvpkM, PublicKeys, TpkM};
use std::embedded_curve_ops::{EmbeddedCurvePoint, EmbeddedCurveScalar, fixed_base_scalar_mul};

use crate::derivation::conversion::MasterSecretKeys;
use crate::derivation::derivation::derive_keys;

/// @notice Derives public keys from master secret keys.
/// @param master_secret_keys The master secret keys
/// @return PublicKeys containing the derived public keys.
pub fn master_secret_keys_to_public_keys(master_secret_keys: MasterSecretKeys) -> PublicKeys {
    let npk_m: EmbeddedCurvePoint =
        fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(master_secret_keys.nsk_m));
    let ivpk_m: EmbeddedCurvePoint =
        fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(master_secret_keys.ivsk_m));
    let ovpk_m: EmbeddedCurvePoint =
        fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(master_secret_keys.ovsk_m));
    let tpk_m: EmbeddedCurvePoint =
        fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(master_secret_keys.tsk_m));

    PublicKeys {
        npk_m: NpkM { inner: npk_m },
        ivpk_m: IvpkM { inner: ivpk_m },
        ovpk_m: OvpkM { inner: ovpk_m },
        tpk_m: TpkM { inner: tpk_m },
    }
}

/// @notice Derives public keys from a secret key (full pipeline: sk -> msks -> pks).
/// @param secret_key The secret key
/// @return PublicKeys containing the derived public keys.
pub fn secret_key_to_public_keys(secret_key: Field) -> PublicKeys {
    let msks = derive_keys(secret_key);
    master_secret_keys_to_public_keys(msks)
}
