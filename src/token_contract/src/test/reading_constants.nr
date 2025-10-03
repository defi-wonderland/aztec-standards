use crate::test::utils;
use crate::Token;

// It is not possible to deserialize strings in Noir ATM, so name and symbol cannot be checked yet.

#[test]
unconstrained fn check_decimals() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, _, _, _) = utils::setup_with_minter(false);

    // Check decimals
    let result = env.view_public(Token::at(token_contract_address).decimals());

    assert(result == 18);
}
