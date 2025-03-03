use crate::ClawbackEscrow;
use crate::test::utils;

#[test]
unconstrained fn sender_can_clawback() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, clawback_escrow_contract_address, escrow_contract_address, token_contract_address, owner, recipient) =
        utils::setup(true, mint_amount);

    // Create the clawback escrow
    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .create_clawback_escrow(escrow_contract_address, recipient)
        .call(&mut env.private());

    env.advance_block_by(1);

    utils::check_private_balance(token_contract_address, escrow_contract_address, mint_amount);

    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .clawback(escrow_contract_address, token_contract_address, mint_amount)
        .call(&mut env.private());
}

#[test(should_fail_with = "Only sender can clawback")]
unconstrained fn only_sender_can_clawback() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, clawback_escrow_contract_address, escrow_contract_address, token_contract_address, owner, recipient) =
        utils::setup(true, mint_amount);

    // Create the clawback escrow
    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .create_clawback_escrow(escrow_contract_address, recipient)
        .call(&mut env.private());

    env.advance_block_by(1);

    utils::check_private_balance(token_contract_address, escrow_contract_address, mint_amount);

    env.impersonate(recipient);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .clawback(escrow_contract_address, token_contract_address, mint_amount)
        .call(&mut env.private());
}

// #[test(should_fail_with = "Balance too low")]
#[test(should_fail)]
unconstrained fn cannot_clawback_more_than_escrowed_amount() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, clawback_escrow_contract_address, escrow_contract_address, token_contract_address, owner, recipient) =
        utils::setup(true, mint_amount);

    // Create the clawback escrow
    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .create_clawback_escrow(escrow_contract_address, recipient)
        .call(&mut env.private());

    env.advance_block_by(1);

    utils::check_private_balance(token_contract_address, escrow_contract_address, mint_amount);

    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .clawback(
            escrow_contract_address,
            token_contract_address,
            mint_amount + U128::from_integer(1),
        )
        .call(&mut env.private());
}

#[test]
unconstrained fn can_clawback_multiple_times() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, clawback_escrow_contract_address, escrow_contract_address, token_contract_address, owner, recipient) =
        utils::setup(true, mint_amount);

    // Create the clawback escrow
    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .create_clawback_escrow(escrow_contract_address, recipient)
        .call(&mut env.private());

    env.advance_block_by(1);

    utils::check_private_balance(token_contract_address, escrow_contract_address, mint_amount);

    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .clawback(
            escrow_contract_address,
            token_contract_address,
            mint_amount / U128::from_integer(2),
        )
        .call(&mut env.private());

    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .clawback(
            escrow_contract_address,
            token_contract_address,
            mint_amount / U128::from_integer(2),
        )
        .call(&mut env.private());
}

