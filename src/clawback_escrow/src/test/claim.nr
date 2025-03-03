use crate::ClawbackEscrow;
use crate::test::utils;
use dep::token::test::utils as token_utils;

#[test]
unconstrained fn recipient_can_claim() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, clawback_escrow_contract_address, escrow_contract_address, token_contract_address, owner, recipient) =
        utils::setup(true, mint_amount);

    // Create the clawback escrow
    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .create_clawback_escrow(escrow_contract_address, recipient)
        .call(&mut env.private());

    env.advance_block_by(1);

    token_utils::check_private_balance(
        token_contract_address,
        escrow_contract_address,
        mint_amount,
    );

    env.impersonate(recipient);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .claim(escrow_contract_address, token_contract_address, mint_amount)
        .call(&mut env.private());
}

// TODO(#33):
// #[test(should_fail_with = "Balance too low")]
#[test(should_fail)]
unconstrained fn recipient_cannot_claim_more_than_escrowed_amount() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, clawback_escrow_contract_address, escrow_contract_address, token_contract_address, owner, recipient) =
        utils::setup(true, mint_amount);

    // Create the clawback escrow
    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .create_clawback_escrow(escrow_contract_address, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    token_utils::check_private_balance(
        token_contract_address,
        escrow_contract_address,
        mint_amount,
    );

    env.impersonate(recipient);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .claim(escrow_contract_address, token_contract_address, mint_amount + U128::from_integer(1))
        .call(&mut env.private());
}

#[test(should_fail_with = "Only receiver can claim")]
unconstrained fn only_recipient_can_claim() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, clawback_escrow_contract_address, escrow_contract_address, token_contract_address, owner, recipient) =
        utils::setup(true, mint_amount);

    // Create the clawback escrow
    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .create_clawback_escrow(escrow_contract_address, recipient)
        .call(&mut env.private());

    env.advance_block_by(1);

    token_utils::check_private_balance(
        token_contract_address,
        escrow_contract_address,
        mint_amount,
    );

    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .claim(escrow_contract_address, token_contract_address, mint_amount)
        .call(&mut env.private());

    token_utils::check_private_balance(token_contract_address, recipient, mint_amount);
}

#[test]
unconstrained fn recipient_can_claim_multiple_times() {
    let mint_amount = U128::from_integer(1_000_000_000);
    let (env, clawback_escrow_contract_address, escrow_contract_address, token_contract_address, owner, recipient) =
        utils::setup(true, mint_amount);

    // Create the clawback escrow
    env.impersonate(owner);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .create_clawback_escrow(escrow_contract_address, recipient)
        .call(&mut env.private());

    env.advance_block_by(1);

    token_utils::check_private_balance(
        token_contract_address,
        escrow_contract_address,
        mint_amount,
    );

    env.impersonate(recipient);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .claim(escrow_contract_address, token_contract_address, mint_amount / U128::from_integer(2))
        .call(&mut env.private());

    env.impersonate(recipient);
    ClawbackEscrow::at(clawback_escrow_contract_address)
        .claim(escrow_contract_address, token_contract_address, mint_amount / U128::from_integer(2))
        .call(&mut env.private());

    token_utils::check_private_balance(token_contract_address, recipient, mint_amount);
    token_utils::check_private_balance(
        token_contract_address,
        escrow_contract_address,
        U128::from_integer(0),
    );
}
