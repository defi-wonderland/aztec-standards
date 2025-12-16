use crate::test::utils as logic_utils;
use crate::TestLogic;
use aztec::{
    oracle::get_contract_instance::get_contract_instance,
    protocol_types::{
        address::AztecAddress,
        contract_instance::ContractInstance,
        traits::{FromField, ToField},
    },
};
use aztec::test::helpers::test_environment::TestEnvironment;
use escrow_contract::test::utils as escrow_utils;

// TODO: Testing that get_escrow succeeds with a deployed escrow contract is not possible given that custom salt
// is not supported yet in the test environment. Testing deployer and initialization hash has the same problem,
// it is not possible to deploy a contract with public keys and constructor/deployer
// https://github.com/AztecProtocol/aztec-packages/issues/16656
#[test(should_fail_with = "Salt is not the logic contract")]
unconstrained fn get_escrow_correct_instance() {
    let mut env = TestEnvironment::new();

    // Secret keys derived using a different seed than 1, hence the public keys will not match
    let secret = 1;
    let (public_keys, msk, _, _) = logic_utils::get_test_vector();

    let _ = escrow_utils::deploy_escrow_with_secret(&mut env, secret);

    let escrow_class_id = escrow_utils::get_escrow_class_id();

    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);

    let caller = env.create_light_account();
    let escrow = env.call_private(caller, TestLogic::at(logic).get_escrow(msk));

    let escrow_instance: ContractInstance = get_contract_instance(escrow);

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

    // Secret key derived using 1 as the seed
    let secret = 1;
    let (_, _, _, incorrect_msk) = logic_utils::get_test_vector();

    let escrow = escrow_utils::deploy_escrow_with_secret(&mut env, secret);

    let escrow_class_id = escrow_utils::get_escrow_class_id();

    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);

    let caller = env.create_light_account();
    let expected_escrow_address =
        env.call_private(caller, TestLogic::at(logic).get_escrow(incorrect_msk));

    assert_eq(escrow, expected_escrow_address, "Escrow address mismatch");
}

#[test(should_fail_with = "Escrow address mismatch")]
unconstrained fn get_escrow_class_id_mismatch() {
    let mut env = TestEnvironment::new();

    // Secret key derived using 1 as the seed
    let secret = 1;
    let (_, msk, _, _) = logic_utils::get_test_vector();

    let escrow = escrow_utils::deploy_escrow_with_secret(&mut env, secret);

    let escrow_class_id = escrow_utils::get_escrow_class_id();

    // We deploy with a different class id, so the test should fail
    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id + 1);

    let owner = env.create_light_account();
    let expected_escrow_address = env.call_private(owner, TestLogic::at(logic).get_escrow(msk));

    assert_eq(escrow, expected_escrow_address, "Escrow address mismatch");
}

#[test(should_fail_with = "Escrow address mismatch")]
unconstrained fn get_escrow_salt_mismatch() {
    let mut env = TestEnvironment::new();

    // Secret key derived using 1 as the seed
    let secret = 1;
    let (_, msk, _, _) = logic_utils::get_test_vector();

    let escrow = escrow_utils::deploy_escrow_with_secret(&mut env, secret);

    let escrow_class_id = escrow_utils::get_escrow_class_id();

    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);

    let owner = env.create_light_account();
    let expected_escrow_address = env.call_private(owner, TestLogic::at(logic).get_escrow(msk));

    assert_eq(escrow, expected_escrow_address, "Escrow address mismatch");
}
