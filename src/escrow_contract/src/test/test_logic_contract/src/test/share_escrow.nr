use crate::test::utils as logic_utils;
use crate::TestLogic;
use aztec::{
    capsules::CapsuleArray,
    messages::processing::{get_private_logs, pending_tagged_log::PendingTaggedLog},
    test::helpers::test_environment::TestEnvironment,
    utils::array,
};

// TODO: This test is skipped because it needs to be updated to work with the new sync private state
// Sync private state after env.advance_block_by(1);
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
    TestLogic::at(logic).share_escrow(recipient, escrow, sk[0], sk[1], sk[2], sk[3]).call(
        &mut env.private(),
    );

    env.advance_block_by(1);

    let mut logs: CapsuleArray<PendingTaggedLog> = get_private_logs(sender);
    println(logs);
}
