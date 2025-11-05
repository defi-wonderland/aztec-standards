use crate::test::utils as logic_utils;
use crate::TestLogic;
use aztec::{
    protocol_types::traits::ToField,
    test::helpers::{test_environment::TestEnvironment, txe_oracles},
};

// TODO: Testing that check_escrow succeeds is not possible given that custom salt is not supported yet in the test environment,
// it will always revert with "Escrow salt should be equal to the this address"
// Testing deployer and initialization hash has the same problem, it is not possible to deploy a contract with public keys and constructor/deployer
// https://github.com/AztecProtocol/aztec-packages/issues/16656

#[test(should_fail_with = "Assertion failed: Escrow public keys mismatch")]
unconstrained fn check_escrow_public_keys_mismatch() {
    let mut env = TestEnvironment::new();

    // Secret keys derived using a different seed than 1, hence the public keys will not match
    let secret = 1;
    let (_, _, _, incorrect_msk) = logic_utils::get_test_vector();

    let escrow = logic_utils::deploy_escrow_with_secret(&mut env, secret);

    let escrow_class_id = logic_utils::get_escrow_class_id();

    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);

    let caller = env.create_light_account();
    env.call_private(caller, TestLogic::at(logic).check_escrow(escrow, incorrect_msk));
}

#[test(should_fail_with = "Assertion failed: Escrow class id mismatch")]
unconstrained fn check_escrow_class_id_mismatch() {
    let mut env = TestEnvironment::new();

    // Secret key derived using 1 as the seed
    let secret = 1;
    let (_, msk, _, _) = logic_utils::get_test_vector();

    let escrow = logic_utils::deploy_escrow_with_secret(&mut env, secret);

    let escrow_class_id = logic_utils::get_escrow_class_id();

    // We deploy with a different class id, so the test should fail
    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id + 1);

    let owner = env.create_light_account();
    env.call_private(owner, TestLogic::at(logic).check_escrow(escrow, msk));
}

#[test(should_fail_with = "Assertion failed: Escrow salt mismatch")]
unconstrained fn check_escrow_salt_mismatch() {
    let mut env = TestEnvironment::new();

    // Secret key derived using 1 as the seed
    let secret = 1;
    let (_, msk, _, _) = logic_utils::get_test_vector();

    let escrow = logic_utils::deploy_escrow_with_secret(&mut env, secret);

    let escrow_class_id = logic_utils::get_escrow_class_id();

    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);

    let owner = env.create_light_account();
    env.call_private(owner, TestLogic::at(logic).check_escrow(escrow, msk));
}
