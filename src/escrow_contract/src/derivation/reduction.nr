use crate::derivation::constants::FQ_MODULUS_BYTES_PADDED;
use bignum::BigNum;
use bignum::{BN254_Fq, U512};

/// Pads a 64-byte array to 65 bytes by prepending a zero byte
/// This is needed because U512 has 513 MOD_BITS, requiring 65 bytes
fn pad_to_65_bytes(hash: [u8; 64]) -> [u8; 65] {
    let mut padded: [u8; 65] = [0; 65];
    // First byte is 0 (already set), copy hash to remaining 64 bytes
    for i in 0..64 {
        padded[i + 1] = hash[i];
    }
    padded
}

/// Pads the Fq modulus constant to 65 bytes
fn get_fq_modulus_65_bytes() -> [u8; 65] {
    let mut padded: [u8; 65] = [0; 65];
    for i in 0..64 {
        padded[i + 1] = FQ_MODULUS_BYTES_PADDED[i];
    }
    padded
}

/// Reduces a 64-byte SHA512 hash to BN254_Fq (GrumpkinScalar)
/// This performs: result = hash_value % Fq.MODULUS
///
/// The 512-bit hash is interpreted as a big-endian integer and reduced
/// modulo the Fq modulus to produce a valid GrumpkinScalar.
pub fn reduce_to_grumpkin_scalar(hash: [u8; 64]) -> BN254_Fq {
    // Pad hash to 65 bytes for U512 (which has 513 MOD_BITS)
    let hash_padded = pad_to_65_bytes(hash);
    let fq_modulus_padded = get_fq_modulus_65_bytes();

    // Convert to U512
    let hash_value: U512 = U512::from_be_bytes(hash_padded);
    let fq_modulus: U512 = U512::from_be_bytes(fq_modulus_padded);

    // Compute hash_value mod fq_modulus
    // udiv_mod returns (quotient, remainder)
    let (_, remainder) = hash_value.udiv_mod(fq_modulus);

    // The remainder fits in 254 bits, extract to BN254_Fq
    // BN254_Fq has 3 limbs of 120 bits each
    let result = BN254_Fq::from_limbs([
        remainder.get_limb(0),
        remainder.get_limb(1),
        remainder.get_limb(2),
    ]);

    // Validate the result is in range
    result.validate_in_field();

    result
}
