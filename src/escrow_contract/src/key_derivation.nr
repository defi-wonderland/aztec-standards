use bignum::bignum::BigNum;
use bignum::U512;
use sha512::sha512;

use aztec::protocol::constants::{DOM_SEP__IVSK_M, DOM_SEP__NHK_M, DOM_SEP__OVSK_M, DOM_SEP__TSK_M};
use aztec::protocol::public_keys::{IvpkM, NpkM, OvpkM, PublicKeys, TpkM};
use std::embedded_curve_ops::{EmbeddedCurvePoint, EmbeddedCurveScalar, fixed_base_scalar_mul};

pub use crate::types::master_secret_keys::MasterSecretKeys;

// ============ Constants ============

/// 2^120 as a Field constant for U512 limb reconstruction
global TWO_POW_120: Field = 0x1000000000000000000000000000000;
/// 2^240 as a Field constant for U512 limb reconstruction
global TWO_POW_240: Field = 0x1000000000000000000000000000000000000000000000000000000000000;

/// Fq modulus (BN254 base field / Grumpkin scalar field) as U512 limbs (little-endian, 120-bit each)
/// Fq.MODULUS = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
global FQ_MODULUS_U512: U512 = U512::from_limbs([
    0x816a916871ca8d3c208c16d87cfd47,
    0x4e72e131a029b85045b68181585d97,
    0x3064,
    0,
    0,
]);

// ============ Internal helpers ============

/// Reduces a 64-byte SHA512 hash modulo the Fq modulus, returning a Field
/// This performs: result = hash_value % Fq.MODULUS
fn reduce_to_field(hash: [u8; 64]) -> Field {
    // Pad hash to 65 bytes for U512 (which has 513 MOD_BITS)
    let mut hash_padded: [u8; 65] = [0; 65];
    for i in 0..64 {
        hash_padded[i + 1] = hash[i];
    }

    let hash_value: U512 = U512::from_be_bytes(hash_padded);
    let (_, remainder) = hash_value.udiv_mod(FQ_MODULUS_U512);

    // Convert U512 remainder directly to Field via limb reconstruction
    // remainder < Fq modulus < Field modulus, so no additional validation needed
    (remainder.get_limb(0) as Field)
        + (remainder.get_limb(1) as Field) * TWO_POW_120
        + (remainder.get_limb(2) as Field) * TWO_POW_240
}

/// Sets the generator index bytes in the last 4 bytes of the buffer
fn set_generator_index(buffer: &mut [u8; 36], generator_index: u32) {
    buffer[32] = ((generator_index >> 24) & 0xff) as u8;
    buffer[33] = ((generator_index >> 16) & 0xff) as u8;
    buffer[34] = ((generator_index >> 8) & 0xff) as u8;
    buffer[35] = (generator_index & 0xff) as u8;
}

/// Computes SHA512 of the buffer and reduces the result to a Field
fn hash_and_reduce(buffer: [u8; 36]) -> Field {
    let hash = sha512::digest(buffer);
    reduce_to_field(hash)
}

/// Derives a master secret key from a secret key and generator index
/// using SHA512 followed by modular reduction to Fq
fn sha512_to_grumpkin_scalar(secret_key: Field, generator_index: u32) -> Field {
    let mut buffer: [u8; 36] = [0; 36];
    let sk_bytes: [u8; 32] = secret_key.to_be_bytes();
    for i in 0..32 {
        buffer[i] = sk_bytes[i];
    }
    set_generator_index(&mut buffer, generator_index);
    hash_and_reduce(buffer)
}

// ============ Public API ============

/// Derive master nullifier secret key (nsk_m) from secret key
pub fn derive_master_nullifier_secret_key(secret_key: Field) -> Field {
    sha512_to_grumpkin_scalar(secret_key, DOM_SEP__NHK_M)
}

/// Derive master incoming viewing secret key (ivsk_m) from secret key
pub fn derive_master_incoming_viewing_secret_key(secret_key: Field) -> Field {
    sha512_to_grumpkin_scalar(secret_key, DOM_SEP__IVSK_M)
}

/// Derive master outgoing viewing secret key (ovsk_m) from secret key
pub fn derive_master_outgoing_viewing_secret_key(secret_key: Field) -> Field {
    sha512_to_grumpkin_scalar(secret_key, DOM_SEP__OVSK_M)
}

/// Derive master tagging secret key (tsk_m) from secret key
pub fn derive_master_tagging_secret_key(secret_key: Field) -> Field {
    sha512_to_grumpkin_scalar(secret_key, DOM_SEP__TSK_M)
}

/// Derive all four master secret keys at once from a secret key
/// Optimized to serialize the secret key only once and reuse the buffer
pub fn derive_keys(secret_key: Field) -> MasterSecretKeys {
    let sk_bytes: [u8; 32] = secret_key.to_be_bytes();
    let mut buffer: [u8; 36] = [0; 36];
    for i in 0..32 {
        buffer[i] = sk_bytes[i];
    }

    set_generator_index(&mut buffer, DOM_SEP__NHK_M);
    let nsk_m = hash_and_reduce(buffer);

    set_generator_index(&mut buffer, DOM_SEP__IVSK_M);
    let ivsk_m = hash_and_reduce(buffer);

    set_generator_index(&mut buffer, DOM_SEP__OVSK_M);
    let ovsk_m = hash_and_reduce(buffer);

    set_generator_index(&mut buffer, DOM_SEP__TSK_M);
    let tsk_m = hash_and_reduce(buffer);

    MasterSecretKeys { nsk_m, ivsk_m, ovsk_m, tsk_m }
}

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
