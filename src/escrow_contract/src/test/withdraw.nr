use crate::test::utils;
use crate::Escrow;
use dep::token::test::utils as token_utils;

#[test]
unconstrained fn withdraw_from_owner_to_recipient() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, escrow_address, owner, recipient, token_address, escrow_secret) = utils::setup_and_mint(/* with_account_contracts */ true, mint_amount);

    env.impersonate(owner);
    let withdraw_call_interface = Escrow::at(escrow_address).withdraw(token_address, mint_amount, recipient);
    withdraw_call_interface.call(&mut env.private());

    token_utils::check_private_balance(token_address, recipient, mint_amount);
    token_utils::check_private_balance(token_address, escrow_address, U128::from_integer(0));
}

#[test]
unconstrained fn withdraw_twice() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, escrow_address, owner, recipient, token_address, escrow_secret) = utils::setup_and_mint(/* with_account_contracts */ true, mint_amount);

    env.impersonate(owner);
    let half_amount = U128::from_integer(500_000_000);
    let withdraw_call_interface = Escrow::at(escrow_address).withdraw(token_address, half_amount, recipient);
    withdraw_call_interface.call(&mut env.private());

    token_utils::check_private_balance(token_address, recipient, half_amount);
    token_utils::check_private_balance(token_address, escrow_address, half_amount);

    // Second withdrawal
    let withdraw_call_interface = Escrow::at(escrow_address).withdraw(token_address, half_amount, recipient);
    withdraw_call_interface.call(&mut env.private());

    token_utils::check_private_balance(token_address, recipient, mint_amount);
    token_utils::check_private_balance(token_address, escrow_address, U128::from_integer(0));
}

#[test]
unconstrained fn withdraw_to_multiple_recipients() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, escrow_address, owner, recipient, token_address, escrow_secret) = utils::setup_and_mint(/* with_account_contracts */ true, mint_amount);

    env.impersonate(owner);
    let half_amount = U128::from_integer(500_000_000);
    let recipient1 = recipient;
    let withdraw_call_interface = Escrow::at(escrow_address).withdraw(token_address, half_amount, recipient1);
    withdraw_call_interface.call(&mut env.private());

    token_utils::check_private_balance(token_address, recipient1, half_amount);
    token_utils::check_private_balance(token_address, escrow_address, half_amount);

    // Second withdrawal
    let recipient2 = owner;
    let withdraw_call_interface = Escrow::at(escrow_address).withdraw(token_address, half_amount, recipient2);
    withdraw_call_interface.call(&mut env.private());

    token_utils::check_private_balance(token_address, recipient1, half_amount);
    token_utils::check_private_balance(token_address, recipient2, half_amount);
    token_utils::check_private_balance(token_address, escrow_address, U128::from_integer(0));
}

#[test(should_fail_with = "Unauthorized")]
unconstrained fn withdraw_from_self() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, escrow_address, owner, recipient, token_address, escrow_secret) = utils::setup_and_mint(/* with_account_contracts */ true, mint_amount);
    
    env.impersonate(escrow_address);
    let withdraw_call_interface = Escrow::at(escrow_address).withdraw(token_address, mint_amount, recipient);
    withdraw_call_interface.call(&mut env.private());
}

#[test(should_fail_with = "Unauthorized")]
unconstrained fn withdraw_from_recipient() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, escrow_address, owner, recipient, token_address, escrow_secret) = utils::setup_and_mint(/* with_account_contracts */ true, mint_amount);
    
    env.impersonate(recipient);
    let withdraw_call_interface = Escrow::at(escrow_address).withdraw(token_address, mint_amount, recipient);
    withdraw_call_interface.call(&mut env.private());
}

// TODO(#33):
// #[test(should_fail_with = "Balance too low")]
#[test(should_fail)]
unconstrained fn recipient_cannot_withdraw_more_than_escrowed_amount() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, escrow_address, owner, recipient, token_address, escrow_secret) = utils::setup_and_mint(/* with_account_contracts */ true, mint_amount);

    env.impersonate(owner);
    let withdraw_call_interface = Escrow::at(escrow_address).withdraw(token_address, mint_amount + U128::from_integer(1), recipient);
    withdraw_call_interface.call(&mut env.private());
}
