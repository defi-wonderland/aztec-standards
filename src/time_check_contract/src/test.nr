use crate::TimeCheck;
use aztec::{prelude::AztecAddress, test::helpers::test_environment::TestEnvironment};

#[test]
unconstrained fn check_timestamp_greater_than() {
    let (env, time_check_contract_address) = setup();

    // TODO: implement warp to timestamp and check
    TimeCheck::at(time_check_contract_address).timestamp_gt(0).view(&mut env.private());
}

#[test(should_fail_with = "Timestamp not greater than current")]
unconstrained fn check_fail_timestamp_greater_than() {
    let (env, time_check_contract_address) = setup();

    // TODO: implement warp to timestamp and check
    TimeCheck::at(time_check_contract_address).timestamp_gt(0).view(&mut env.private());
}

#[test]
unconstrained fn check_timestamp_lesser_than() {
    let (env, time_check_contract_address) = setup();

    // TODO: implement warp to timestamp and check
    TimeCheck::at(time_check_contract_address).timestamp_gt(0).view(&mut env.private());
}

#[test(should_fail_with = "Timestamp not lesser than current")]
unconstrained fn check_fail_timestamp_lesser_than() {
    let (env, time_check_contract_address) = setup();

    // TODO: implement warp to timestamp and check
    TimeCheck::at(time_check_contract_address).timestamp_gt(0).view(&mut env.private());
}

unconstrained fn setup() -> (&mut TestEnvironment, AztecAddress) {
    let mut env = TestEnvironment::new();

    let time_check_contract = env.deploy_self("TimeCheck").without_initializer();
    let time_check_contract_address = time_check_contract.to_address();
    env.advance_block_by(1);

    (&mut env, time_check_contract_address)
}
