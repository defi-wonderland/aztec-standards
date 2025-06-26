use aztec::{prelude::AztecAddress, protocol_types::{hash::poseidon2_hash_bytes, traits::FromField}};

pub global PRIVATE_OWNER_ADDRESS: AztecAddress =
    AztecAddress::from_field(poseidon2_hash_bytes("PRIVATE_OWNER".as_bytes()));
