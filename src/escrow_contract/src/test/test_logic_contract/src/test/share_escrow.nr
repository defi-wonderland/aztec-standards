use crate::test::utils as logic_utils;
use crate::TestLogic;
use aztec::test::helpers::test_environment::TestEnvironment;
use escrow_contract::test::utils as escrow_utils;

#[test]
unconstrained fn share_escrow_success() {
    let mut env = TestEnvironment::new();

    let recipient = env.create_light_account();
    let sender = env.create_light_account();

    let (_, secret_key, _, _) = logic_utils::get_test_vector();

    let escrow_class_id = escrow_utils::get_escrow_class_id();
    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);
    let escrow = escrow_utils::deploy_escrow_with_secret(&mut env, 1, logic);

    env.call_private(sender, TestLogic::at(logic).share_escrow(recipient, escrow, secret_key));
}
