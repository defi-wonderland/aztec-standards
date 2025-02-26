use crate::test::utils;
use crate::Escrow;

#[test]
unconstrained fn leak_keys_from_owner_to_recipient() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, escrow_contract_address, deployer, owner, recipient) = utils::setup(/* with_account_contracts */ true);

    let leak_keys_call_interface = Escrow::at(escrow_contract_address).leak_keys(recipient);
    // Impersonate owner to perform the call
    env.impersonate(owner);
    // Leak escrow keys
    leak_keys_call_interface.call(&mut env.private());
    // Check balances
    env.impersonate(owner);
    let owner_note: utils::call_view_owner_note();
    println(owner_note);
}

#[test(should_fail_with = "Unauthorized")]
unconstrained fn test_leak_keys_unauthorized_recipient() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, escrow_contract_address, deployer, owner, recipient) = utils::setup(/* with_account_contracts */ true);
    
    let leak_keys_call_interface = Escrow::at(escrow_contract_address).leak_keys(recipient);
    // Impersonate owner to perform the call
    env.impersonate(recipient);
    // Leak escrow keys
    leak_keys_call_interface.call(&mut env.private());
}

#[test(should_fail_with = "Unauthorized")]
unconstrained fn leak_keys_unauthorized_deployer() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, escrow_contract_address, deployer, owner, recipient) = utils::setup(/* with_account_contracts */ true);
    
    let leak_keys_call_interface = Escrow::at(escrow_contract_address).leak_keys(recipient);
    // Impersonate owner to perform the call
    env.impersonate(deployer);
    // Leak escrow keys
    leak_keys_call_interface.call(&mut env.private());
}

