use crate::test::utils;
use crate::Escrow;

#[test]
unconstrained fn leak_keys_from_owner_to_recipient() {
    let (env, escrow_address, owner, recipient, escrow_secret) = utils::setup(/* with_account_contracts */ true);
    
    env.impersonate(owner);
    let leak_keys_call_interface = Escrow::at(escrow_address).leak_keys(recipient);
    leak_keys_call_interface.call(&mut env.private());
}

#[test(should_fail_with = "Unauthorized")]
unconstrained fn leak_keys_from_self() {
    let (env, escrow_address, owner, recipient, escrow_secret) = utils::setup(/* with_account_contracts */ true);
    
    env.impersonate(escrow_address);
    let leak_keys_call_interface = Escrow::at(escrow_address).leak_keys(recipient);
    leak_keys_call_interface.call(&mut env.private());
}

#[test(should_fail_with = "Unauthorized")]
unconstrained fn leak_keys_from_recipient() {
    let (env, escrow_address, owner, recipient, escrow_secret) = utils::setup(/* with_account_contracts */ true);
    
    env.impersonate(recipient);
    let leak_keys_call_interface = Escrow::at(escrow_address).leak_keys(recipient);
    leak_keys_call_interface.call(&mut env.private());
}
