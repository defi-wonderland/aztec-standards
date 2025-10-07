use crate::TokenCaller;
use aztec::{
    protocol_types::address::AztecAddress, test::helpers::test_environment::TestEnvironment,
};
use token::test::utils as token_utils;

pub unconstrained fn setup_with_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, token_contract_address, owner, recipient, minter) =
        token_utils::setup_with_minter(with_account_contracts);

    let token_caller_initializer_call_interface = TokenCaller::interface().constructor();

    let token_caller_contract_address = env
        .deploy("@token_caller/TokenCaller")
        .with_public_initializer(owner, token_caller_initializer_call_interface);

    (env, token_contract_address, owner, recipient, minter, token_caller_contract_address)
}
