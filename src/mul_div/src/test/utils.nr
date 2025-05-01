use crate::MulDiv;
use aztec::{
    oracle::{
        execution::{get_block_number, get_contract_address},
        random::random,
        storage::storage_read,
    },
    prelude::AztecAddress,
    protocol_types::storage::map::derive_storage_slot_in_map,
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
};
use std::test::OracleMock;

pub unconstrained fn setup(
    with_account_contracts: bool,
) -> (&mut TestEnvironment, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let owner = if with_account_contracts {
        env.create_account_contract(1)
    } else {
        env.create_account(1)
    };

    env.impersonate(owner);

    // Deploy MulDiv contract
    let initializer_call_interface = MulDiv::interface().constructor();
    let mul_div_contract = env.deploy("./@mul_div", "MulDiv").with_public_void_initializer(
        initializer_call_interface,
    );
    env.advance_block_by(1);

    let mul_div_contract_address = mul_div_contract.to_address();

    (&mut env, mul_div_contract_address, owner)
}
