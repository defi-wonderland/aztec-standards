use crate::test::utils as logic_utils;
use crate::TestLogic;
use aztec::{
    test::helpers::test_environment::TestEnvironment,
    messages::processing::{get_private_logs, pending_tagged_log::PendingTaggedLog},
    capsules::CapsuleArray,
    utils::array,
};

// This test is skipped because it needs to be updated to work with the new sync private state
// #[test]
unconstrained fn share_escrow_success() {
    let mut env = TestEnvironment::new();

    let recipient = env.create_account(1);
    let sender = env.create_account(2);

    let (_, sk, _, _) = logic_utils::get_test_vector();

    let secret = 1;
    let escrow = logic_utils::deploy_escrow_with_secret(&mut env, secret);

    let logic = logic_utils::deploy_logic(&mut env, 1);


    env.impersonate(sender);
    TestLogic::at(logic).share_escrow(escrow, [sk[0], sk[1], sk[2], sk[3]], recipient).call(&mut env.private());

    env.advance_block_by(1);

    // TODO: sync private state and continue with the test

    let mut logs: CapsuleArray<PendingTaggedLog> = get_private_logs(sender);
    println(logs);
}