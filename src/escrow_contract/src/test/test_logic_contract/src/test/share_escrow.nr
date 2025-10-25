use crate::test::utils as logic_utils;
use crate::TestLogic;
use aztec::{
    oracle::get_contract_instance::get_contract_instance, protocol_types::traits::ToField,
    test::helpers::test_environment::TestEnvironment,
};

// NOTE: This test is disabled because share_escrow validation requires the escrow salt
// to match the logic contract address, which is not possible in v2.0.3 test environment.
// The salt check will always fail with "Escrow salt mismatch".
// Additionally, event emission modules are not accessible in Noir tests.
// Full share_escrow functionality should be tested in TypeScript integration tests.
// See: https://github.com/AztecProtocol/aztec-packages/issues/16656

// TODO: Uncomment the test and remove the allow(dead_code) once the test environment supports custom salts
// #[test]
#[allow(dead_code)]
unconstrained fn share_escrow_success() {
    let mut env = TestEnvironment::new();

    let recipient = env.create_light_account();
    let sender = env.create_light_account();

    let (_, msk, _, _) = logic_utils::get_test_vector();

    let secret = 1;
    let escrow = logic_utils::deploy_escrow_with_secret(&mut env, secret);

    // Get the actual escrow class id
    let escrow_instance = get_contract_instance(escrow);
    let escrow_class_id = escrow_instance.contract_class_id.to_field();

    // Deploy logic contract with the correct escrow class id
    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);

    // This will fail with "Escrow salt mismatch" because we cannot make
    // the escrow salt equal the logic contract address in test environment
    env.call_private(
        sender,
        TestLogic::at(logic).share_escrow(recipient, escrow, msk),
    );
}
