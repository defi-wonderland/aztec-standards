use crate::test::utils;
use crate::MulDiv;

#[test]
unconstrained fn mul_div_in_private() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, contract_address, owner) =
        utils::setup(/* with_account_contracts */ true);

    let x = 1000 as u128;
    let y = 25000 as u128;
    let z = 99 as u128;
    let mul_div_in_private_from_call_interface = MulDiv::at(contract_address)
        .mul_div_in_private(x, y, z);

    env.impersonate(owner);
    mul_div_in_private_from_call_interface.call(&mut env.private());
}