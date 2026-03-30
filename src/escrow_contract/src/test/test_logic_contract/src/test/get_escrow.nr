use crate::test::utils as logic_utils;
use crate::TestLogic;
use aztec::{
    oracle::get_contract_instance::get_contract_instance,
    protocol::{
        address::AztecAddress,
        contract_instance::ContractInstance,
        traits::{FromField, ToField},
    },
};
use aztec::test::helpers::test_environment::TestEnvironment;
use escrow_contract::test::utils as escrow_utils;

#[test]
unconstrained fn get_escrow_correct_instance() {
    let mut env = TestEnvironment::new();

    let (public_keys, secret_key, _, _) = logic_utils::get_test_vector();

    let escrow_class_id = escrow_utils::get_escrow_class_id();
    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);

    let deployed_escrow = escrow_utils::deploy_escrow_with_secret(&mut env, secret_key, logic);

    let caller = env.create_light_account();
    let escrow = env.call_private(caller, TestLogic::at(logic).get_escrow(secret_key));
    assert_eq(deployed_escrow, escrow, "Incorrect escrow deployed");

    let escrow_instance: ContractInstance = env.utility_context(|_| {
        get_contract_instance(escrow)
    });

    assert_eq(escrow_instance.salt, logic.to_field(), "Salt is not the logic contract");
    assert_eq(escrow_instance.deployer, AztecAddress::from_field(0), "Deployer is not zero");
    assert_eq(
        escrow_instance.contract_class_id.to_field(),
        escrow_class_id,
        "Escrow class id mismatch",
    );
    assert_eq(escrow_instance.initialization_hash, 0, "Initialization hash is not zero");
    assert_eq(escrow_instance.public_keys, public_keys, "Public keys mismatch");
}

#[test(should_fail_with = "Escrow address mismatch")]
unconstrained fn get_escrow_public_keys_mismatch() {
    let mut env = TestEnvironment::new();

    let (_, _, _, incorrect_secret_key) = logic_utils::get_test_vector();

    let escrow_class_id = escrow_utils::get_escrow_class_id();
    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);

    let escrow = escrow_utils::deploy_escrow_with_secret(&mut env, 1, logic);

    let caller = env.create_light_account();
    let expected_escrow_address =
        env.call_private(caller, TestLogic::at(logic).get_escrow(incorrect_secret_key));

    assert_eq(escrow, expected_escrow_address, "Escrow address mismatch");
}

#[test(should_fail_with = "Escrow address mismatch")]
unconstrained fn get_escrow_class_id_mismatch() {
    let mut env = TestEnvironment::new();

    let (_, secret_key, _, _) = logic_utils::get_test_vector();

    let escrow_class_id = escrow_utils::get_escrow_class_id();

    // Deploy logic with a different class id so the computed address won't match
    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id + 1);

    let escrow = escrow_utils::deploy_escrow_with_secret(&mut env, 1, logic);

    let owner = env.create_light_account();
    let expected_escrow_address =
        env.call_private(owner, TestLogic::at(logic).get_escrow(secret_key));

    assert_eq(escrow, expected_escrow_address, "Escrow address mismatch");
}

#[test(should_fail_with = "Escrow address mismatch")]
unconstrained fn get_escrow_salt_mismatch() {
    let mut env = TestEnvironment::new();

    let (_, secret_key, _, _) = logic_utils::get_test_vector();

    let escrow_class_id = escrow_utils::get_escrow_class_id();
    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);

    // Deploy escrow with a different address as salt so it won't match the logic contract
    let wrong_salt = env.create_light_account();
    let escrow = escrow_utils::deploy_escrow_with_secret(&mut env, 1, wrong_salt);

    let owner = env.create_light_account();
    let expected_escrow_address =
        env.call_private(owner, TestLogic::at(logic).get_escrow(secret_key));

    assert_eq(escrow, expected_escrow_address, "Escrow address mismatch");
}
