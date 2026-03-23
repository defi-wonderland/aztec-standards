use crate::test::utils as logic_utils;
use crate::TestLogic;
use aztec::test::helpers::test_environment::TestEnvironment;

// We test public key derivation using two different secret keys.
#[test]
unconstrained fn secret_key_to_public_keys_success() {
    let mut env = TestEnvironment::new();

    let logic_contract_address = logic_utils::deploy_logic(&mut env, 1);

    let (vector_public_keys_1, secret_key_1, vector_public_keys_2, secret_key_2) =
        logic_utils::get_test_vector();

    let caller = env.create_light_account();
    let public_keys_1 = env.call_private(
        caller,
        TestLogic::at(logic_contract_address).secret_key_to_public_keys(secret_key_1),
    );

    assert_eq(vector_public_keys_1.npk_m.inner.x, public_keys_1.npk_m.inner.x);
    assert_eq(vector_public_keys_1.npk_m.inner.y, public_keys_1.npk_m.inner.y);
    assert_eq(vector_public_keys_1.ivpk_m.inner.x, public_keys_1.ivpk_m.inner.x);
    assert_eq(vector_public_keys_1.ivpk_m.inner.y, public_keys_1.ivpk_m.inner.y);
    assert_eq(vector_public_keys_1.ovpk_m.inner.x, public_keys_1.ovpk_m.inner.x);
    assert_eq(vector_public_keys_1.ovpk_m.inner.y, public_keys_1.ovpk_m.inner.y);
    assert_eq(vector_public_keys_1.tpk_m.inner.x, public_keys_1.tpk_m.inner.x);
    assert_eq(vector_public_keys_1.tpk_m.inner.y, public_keys_1.tpk_m.inner.y);
    assert_eq(vector_public_keys_1, public_keys_1);

    let public_keys_2 = env.call_private(
        caller,
        TestLogic::at(logic_contract_address).secret_key_to_public_keys(secret_key_2),
    );

    assert_eq(vector_public_keys_2.npk_m.inner.x, public_keys_2.npk_m.inner.x);
    assert_eq(vector_public_keys_2.npk_m.inner.y, public_keys_2.npk_m.inner.y);
    assert_eq(vector_public_keys_2.ivpk_m.inner.x, public_keys_2.ivpk_m.inner.x);
    assert_eq(vector_public_keys_2.ivpk_m.inner.y, public_keys_2.ivpk_m.inner.y);
    assert_eq(vector_public_keys_2.ovpk_m.inner.x, public_keys_2.ovpk_m.inner.x);
    assert_eq(vector_public_keys_2.ovpk_m.inner.y, public_keys_2.ovpk_m.inner.y);
    assert_eq(vector_public_keys_2.tpk_m.inner.x, public_keys_2.tpk_m.inner.x);
    assert_eq(vector_public_keys_2.tpk_m.inner.y, public_keys_2.tpk_m.inner.y);
    assert_eq(vector_public_keys_2, public_keys_2);
}

// Note that this test will fail since we use a different secret key to produce different public keys than expected
#[test(should_fail)]
unconstrained fn secret_key_to_public_keys_fail() {
    let mut env = TestEnvironment::new();

    let logic_contract_address = logic_utils::deploy_logic(&mut env, 1);

    let (vector_public_keys_1, secret_key_1, _, _) = logic_utils::get_test_vector();

    // we modify the secret key by adding 1, which should derive completely different public keys
    let modified_secret_key = secret_key_1 + 1;

    let caller = env.create_light_account();
    let public_keys_1 = env.call_private(
        caller,
        TestLogic::at(logic_contract_address).secret_key_to_public_keys(modified_secret_key),
    );

    assert_eq(vector_public_keys_1, public_keys_1);
}
