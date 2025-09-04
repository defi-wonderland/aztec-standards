use crate::test::utils as logic_utils;
use crate::TestLogic;
use aztec::test::helpers::test_environment::TestEnvironment;

// We test public key derivation using two different secret keys.
#[test]
unconstrained fn secret_keys_to_public_keys_success() {
    let mut env = TestEnvironment::new();

    let logic_contract_address = logic_utils::deploy_logic(&mut env, 1);

    let (vector_public_keys_1, vector_secret_keys_1, vector_public_keys_2, vector_secret_keys_2) =
        logic_utils::get_test_vector();

    let public_keys_1 = TestLogic::at(logic_contract_address)
        .secret_keys_to_public_keys(
            vector_secret_keys_1[0],
            vector_secret_keys_1[1],
            vector_secret_keys_1[2],
            vector_secret_keys_1[3],
        )
        .call(&mut env.private());

    assert_eq(vector_public_keys_1.npk_m.inner.x, public_keys_1.npk_m.inner.x);
    assert_eq(vector_public_keys_1.npk_m.inner.y, public_keys_1.npk_m.inner.y);
    assert_eq(vector_public_keys_1.ivpk_m.inner.x, public_keys_1.ivpk_m.inner.x);
    assert_eq(vector_public_keys_1.ivpk_m.inner.y, public_keys_1.ivpk_m.inner.y);
    assert_eq(vector_public_keys_1.ovpk_m.inner.x, public_keys_1.ovpk_m.inner.x);
    assert_eq(vector_public_keys_1.ovpk_m.inner.y, public_keys_1.ovpk_m.inner.y);
    assert_eq(vector_public_keys_1.tpk_m.inner.x, public_keys_1.tpk_m.inner.x);
    assert_eq(vector_public_keys_1.tpk_m.inner.y, public_keys_1.tpk_m.inner.y);
    assert_eq(vector_public_keys_1, public_keys_1);

    let public_keys_2 = TestLogic::at(logic_contract_address)
        .secret_keys_to_public_keys(
            vector_secret_keys_2[0],
            vector_secret_keys_2[1],
            vector_secret_keys_2[2],
            vector_secret_keys_2[3],
        )
        .call(&mut env.private());

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

// Note that this test will fail since we modify one of the secret keys to produce a different public key than expected
#[test(should_fail)]
unconstrained fn secret_keys_to_public_keys_fail() {
    let mut env = TestEnvironment::new();

    let logic_contract_address = logic_utils::deploy_logic(&mut env, 1);

    let (vector_public_keys_1, vector_secret_keys_1, _, _) = logic_utils::get_test_vector();

    // we modify the first secret key to be 1 greater than the original, which should derive a different public key
    let modified_secret_keys_1 = vector_secret_keys_1[0] + 1;

    let public_keys_1 = TestLogic::at(logic_contract_address)
        .secret_keys_to_public_keys(
            modified_secret_keys_1,
            vector_secret_keys_1[1],
            vector_secret_keys_1[2],
            vector_secret_keys_1[3],
        )
        .call(&mut env.private());

    assert_eq(vector_public_keys_1, public_keys_1);
}
