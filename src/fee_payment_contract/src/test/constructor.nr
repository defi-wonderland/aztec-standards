use crate::FPC;
use crate::test::utils;

/// Test scenario: Attempt to reinitialize the FPC contract.
/// Verifies that calling the constructor again reverts with the expected initialization hash assertion error.
#[test(should_fail_with = "Assertion failed: Initialization hash does not match 'initialization_hash == expected_init'")]
unconstrained fn test_constructor_cannot_be_reinitialized() {
    // Setup environment
    let (env, fpc_address, admin, user, _) = utils::setup();

    // Create a different token address
    let another_token_address = env.create_account(4);

    // Attempt to call constructor again (should fail)
    env.impersonate(admin);
    FPC::at(fpc_address).constructor(another_token_address, user).call(&mut env.public());
}

/// Test scenario: Retrieve the accepted asset address.
/// Verifies that the `get_accepted_asset` view function returns the correct token address set during deployment.
#[test]
unconstrained fn test_get_accepted_asset_returns_correct_address() {
    // Setup environment
    let (env, fpc_address, _, _, token_address) = utils::setup();

    // Get accepted asset via view function
    let accepted_asset = FPC::at(fpc_address).get_accepted_asset().view(&mut env.private());

    // Assert it matches the deployed token address
    assert(accepted_asset == token_address);
}

// TODO: Implement this test
unconstrained fn test_get_admin_address() {}
