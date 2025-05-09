use crate::MulDiv;
use crate::test::utils;

use bignum_field::bignum_field::BigNumField;

#[test]
unconstrained fn mul_div_in_public() {
    let (env, contract_address, owner) = utils::setup(/* with_account_contracts */ true);

    let x = BigNumField::new(1000);
    let y = BigNumField::new(25000);
    let z = BigNumField::new(99);
    let mul_div_in_public_from_call_interface =
        MulDiv::at(contract_address).mul_div_in_public(x, y, z);

    env.impersonate(owner);
    mul_div_in_public_from_call_interface.call(&mut env.public());
}
