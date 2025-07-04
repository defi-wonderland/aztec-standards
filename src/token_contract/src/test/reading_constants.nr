use crate::test::utils;
use crate::Token;
use aztec::test::helpers::cheatcodes;

// It is not possible to deserialize strings in Noir ATM, so name and symbol cannot be checked yet.

#[test]
unconstrained fn test_reading_constants() {
    // Setup once without account contracts since we're just reading constants
    let (env, token_contract_address, _, _, _) = utils::setup_with_minter(false);
    
    // Check decimals from private context
    let decimals_private = Token::at(token_contract_address).private_get_decimals().view(&mut env.private());
    assert(decimals_private == 18);
    
    // Check decimals from public context
    let decimals_public = Token::at(token_contract_address).public_get_decimals().view(&mut env.public());
    assert(decimals_public == 18);
    
    // Verify both contexts return the same value
    assert(decimals_private == decimals_public);
}