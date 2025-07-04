use crate::{test::utils, Token};

#[test]
unconstrained fn test_mint_to_public() {
    // Setup once without account contracts since we're not using authwits
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);
    
    // Calculate max u128 for overflow tests
    let two_pow_127 = 2.pow_32(127);
    let two_pow_127_minus_one = two_pow_127 - 1;
    let max_u128 = (two_pow_127_minus_one + two_pow_127_minus_one) as u128;
    
    // Success case: Mint to public
    env.impersonate(minter);
    let mint_amount: u128 = 10_000;
    Token::at(token_contract_address).mint_to_public(owner, mint_amount).call(&mut env.public());
    
    utils::check_public_balance(token_contract_address, owner, mint_amount);
    let total_supply = Token::at(token_contract_address).total_supply().view(&mut env.public());
    assert(total_supply == mint_amount);
    
    // Failure case 1: Non-minter trying to mint
    // "caller is not minter"
    env.impersonate(recipient);
    let unauthorized_mint_call = Token::at(token_contract_address).mint_to_public(owner, mint_amount);
    env.assert_public_call_fails(unauthorized_mint_call);
    
    utils::check_public_balance(token_contract_address, owner, mint_amount);
    
    // Failure case 2: Overflow recipient balance
    // First mint max_u128 to recipient
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_public(recipient, max_u128).call(&mut env.public());
    
    // Now try to mint 1 more to recipient which should overflow
    let overflow_mint_call = Token::at(token_contract_address).mint_to_public(recipient, 1 as u128);
    env.assert_public_call_fails(overflow_mint_call);
    
    utils::check_public_balance(token_contract_address, owner, mint_amount);
    utils::check_total_supply(token_contract_address, max_u128 + mint_amount);
    
    // Failure case 3: Overflow total supply
    // Try to mint more when we're already at max
    let total_supply_overflow_call = Token::at(token_contract_address).mint_to_public(owner, max_u128);
    env.assert_public_call_fails(total_supply_overflow_call);
    
    utils::check_public_balance(token_contract_address, owner, mint_amount);
}