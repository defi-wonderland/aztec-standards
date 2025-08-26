use token::Token;
use crate::Escrow;
use aztec::{
    prelude::AztecAddress,
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
};

pub unconstrained fn deploy_escrow(escrow_secret: Field) -> (&mut TestEnvironment, AztecAddress) {
    let mut env = TestEnvironment::new();

    // Deploy escrow contract
    let escrow_contract_account = cheatcodes::add_account(escrow_secret);

    let escrow_contract = env
        .deploy_self_with_public_keys("Escrow", escrow_secret)
        .without_initializer();
    env.advance_block_by(1);

    (&mut env, escrow_contract.to_address())
}