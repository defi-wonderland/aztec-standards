use dep::escrow_contract::Escrow;
use dep::token::test::utils as token_utils;
use aztec::{prelude::AztecAddress, test::helpers::{cheatcodes, test_environment::TestEnvironment}};

pub unconstrained fn setup(
    with_account_contracts: bool,
    mint_amount: U128,
) -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let (owner, recipient) = if with_account_contracts {
        let owner = env.create_account_contract(1);
        let recipient = env.create_account_contract(2);
        (owner, recipient)
    } else {
        let owner = env.create_account(1);
        let recipient = env.create_account(2);
        (owner, recipient)
    };

    let token_contract_address = token_utils::deploy_token(&mut env, owner);

    // Mint private tokens to owner
    env.impersonate(owner);
    token_utils::mint_to_private(&mut env, token_contract_address, owner, mint_amount);

    // Deploy clawback escrow contract
    env.impersonate(owner);
    let clawback_escrow_contract = env.deploy_self("ClawbackEscrow").without_initializer();
    let clawback_escrow_address = clawback_escrow_contract.to_address();
    env.advance_block_by(1);

    dep::aztec::oracle::debug_log::debug_log("Deploying escrow contract");

    // Deploy the escrow
    let escrow_secret = 42069;
    let escrow_contract_account = cheatcodes::add_account(escrow_secret);
    let initializer_call_escrow =
        Escrow::interface().constructor(clawback_escrow_address, escrow_secret);

    let escrow_contract = env
        .deploy_with_public_keys("./@escrow_contract", "Escrow", escrow_secret)
        .with_private_initializer(initializer_call_escrow);
    let escrow_address = escrow_contract.to_address();
    env.advance_block_by(1);

    dep::aztec::oracle::debug_log::debug_log_format(
        "TOKEN ADDRESS: {0}",
        [token_contract_address.to_field()],
    );
    dep::aztec::oracle::debug_log::debug_log_format(
        "CLAWBACK ADDRESS: {0}",
        [clawback_escrow_address.to_field()],
    );
    dep::aztec::oracle::debug_log::debug_log_format(
        "ESCROW ADDRESS: {0}",
        [escrow_address.to_field()],
    );

    // Fund the escrow
    token_utils::transfer_in_private(
        &mut env,
        owner,
        token_contract_address,
        escrow_address,
        mint_amount,
    );

    (&mut env, clawback_escrow_address, escrow_address, token_contract_address, owner, recipient)
}
