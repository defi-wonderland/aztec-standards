/// Serializes a Field (Fr) and a u32 generator index into a 36-byte array
/// Format: [32 bytes Fr (big-endian)] || [4 bytes u32 (big-endian)]
///
/// This matches the TypeScript serializeToBuffer([secretKey, generatorIndex]) behavior
/// from @aztec/foundation/serialize
pub fn serialize_to_buffer(secret_key: Field, generator_index: u32) -> [u8; 36] {
    let mut buffer: [u8; 36] = [0; 36];

    // Serialize secret_key (Fr) as 32 bytes big-endian
    let sk_bytes: [u8; 32] = secret_key.to_be_bytes();
    for i in 0..32 {
        buffer[i] = sk_bytes[i];
    }

    // Serialize generator_index as 4 bytes big-endian
    buffer[32] = ((generator_index >> 24) & 0xff) as u8;
    buffer[33] = ((generator_index >> 16) & 0xff) as u8;
    buffer[34] = ((generator_index >> 8) & 0xff) as u8;
    buffer[35] = (generator_index & 0xff) as u8;

    buffer
}
