//! Helpers for PoC tests: mirror Token capsule slots and pre-seed PXE capsules before calls.
use aztec::{
    capsules::CapsuleArray,
    oracle::capsules::store,
    protocol::{address::AztecAddress, hash::poseidon2_hash_with_separator},
    test::helpers::test_environment::TestEnvironment,
};

// Must match `Token` globals in main.nr
pub global LABEL_SEPARATOR: Field = 0x4c4142454c;
pub global SPEND_LABELS_BASE_SLOT: Field = 0x10000000;
pub global QUERY_LABEL_SLOT: Field = 0x30000000;

/// Mirrors `Token::_label`: the private origin bucket for a `seed` (mint or re-entry). The contract
/// derives the seed from `random()`; tests pin it by mocking the `getRandomField` oracle.
pub fn origin_label(seed: Field) -> Field {
    poseidon2_hash_with_separator([seed], LABEL_SEPARATOR)
}

pub unconstrained fn set_query_label(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    owner: AztecAddress,
    label: Field,
) {
    env.utility_context_at(token_contract_address, |context| {
        let contract_address = context.this_address();
        store(contract_address, QUERY_LABEL_SLOT, label, owner);
    });
}

pub unconstrained fn push_spend_label(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    account: AztecAddress,
    label: Field,
) {
    env.utility_context_at(token_contract_address, |context| {
        let contract_address = context.this_address();
        let queue: CapsuleArray<Field> =
            CapsuleArray::at(contract_address, SPEND_LABELS_BASE_SLOT, account);
        queue.push(label);
    });
}

pub unconstrained fn clear_spend_labels(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    account: AztecAddress,
) {
    env.utility_context_at(token_contract_address, |context| {
        let contract_address = context.this_address();
        let queue: CapsuleArray<Field> =
            CapsuleArray::at(contract_address, SPEND_LABELS_BASE_SLOT, account);
        while queue.len() > 0 {
            queue.remove(0);
        }
    });
}
