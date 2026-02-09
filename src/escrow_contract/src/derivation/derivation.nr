use bignum::bignum::to_field;
use sha512::sha512;

use crate::derivation::conversion::MasterSecretKeys;
use crate::derivation::reduction::reduce_to_grumpkin_scalar;
use crate::derivation::serialization::serialize_to_buffer;
use aztec::protocol_types::constants::{
    GENERATOR_INDEX__IVSK_M, GENERATOR_INDEX__NSK_M, GENERATOR_INDEX__OVSK_M,
    GENERATOR_INDEX__TSK_M,
};

/// Derives a master secret key from a secret key and generator index
/// using SHA512 followed by modular reduction to Fq
///
/// This matches the TypeScript implementation:
/// sha512ToGrumpkinScalar([secretKey, generatorIndex])
fn sha512_to_grumpkin_scalar(secret_key: Field, generator_index: u32) -> Field {
    // Serialize inputs: [32 bytes secret_key] || [4 bytes generator_index]
    let buffer = serialize_to_buffer(secret_key, generator_index);

    // Compute SHA512 hash (64 bytes output)
    let hash = sha512::digest(buffer);

    // Reduce hash modulo Fq to get GrumpkinScalar
    let result = reduce_to_grumpkin_scalar(hash);

    // Convert to Field
    to_field(result)
}

// ============ Public API ============

/// Derive master nullifier secret key (nsk_m) from secret key
///
/// nsk_m is used for nullifying notes - proving that a note has been spent
/// without revealing which note was spent.
pub fn derive_master_nullifier_secret_key(secret_key: Field) -> Field {
    sha512_to_grumpkin_scalar(secret_key, GENERATOR_INDEX__NSK_M)
}

/// Derive master incoming viewing secret key (ivsk_m) from secret key
///
/// ivsk_m is used to decrypt incoming notes - notes that are sent to you.
pub fn derive_master_incoming_viewing_secret_key(secret_key: Field) -> Field {
    sha512_to_grumpkin_scalar(secret_key, GENERATOR_INDEX__IVSK_M)
}

/// Derive master outgoing viewing secret key (ovsk_m) from secret key
///
/// ovsk_m is used to decrypt outgoing notes - notes that you sent to others.
pub fn derive_master_outgoing_viewing_secret_key(secret_key: Field) -> Field {
    sha512_to_grumpkin_scalar(secret_key, GENERATOR_INDEX__OVSK_M)
}

/// Derive master tagging secret key (tsk_m) from secret key
///
/// tsk_m is used for note tagging/discovery.
pub fn derive_master_tagging_secret_key(secret_key: Field) -> Field {
    sha512_to_grumpkin_scalar(secret_key, GENERATOR_INDEX__TSK_M)
}

/// Derive all four master secret keys at once from a secret key
///
/// Returns MasterSecretKeys struct with nsk_m, ivsk_m, ovsk_m, tsk_m
pub fn derive_keys(secret_key: Field) -> MasterSecretKeys {
    MasterSecretKeys {
        nsk_m: derive_master_nullifier_secret_key(secret_key),
        ivsk_m: derive_master_incoming_viewing_secret_key(secret_key),
        ovsk_m: derive_master_outgoing_viewing_secret_key(secret_key),
        tsk_m: derive_master_tagging_secret_key(secret_key),
    }
}
