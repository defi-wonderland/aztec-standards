use crate::test::utils;
use crate::Token;
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::oracle::random::random;

#[test]
unconstrained fn test_burn_public() {
    // Setup once with account contracts since we need authwit
    let (env, token_contract_address, owner, recipient) = utils::setup_with_minter(true);
    let minter = owner; // Owner is the minter in this setup
    
    // Mint a large amount once for all tests
    let initial_mint_amount: u128 = 1_000_000;
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_public(owner, initial_mint_amount).call(&mut env.public());
    
    // Track balances throughout tests
    let mut owner_balance = initial_mint_amount;
    let mut total_supply = initial_mint_amount;
    utils::check_public_balance(token_contract_address, owner, owner_balance);
    utils::check_total_supply(token_contract_address, total_supply);
    
    // Success case 1: Burn less than balance
    env.impersonate(owner);
    let burn_amount_1 = 10_000;
    Token::at(token_contract_address).burn_public(owner, burn_amount_1, 0).call(&mut env.public());
    owner_balance -= burn_amount_1;
    total_supply -= burn_amount_1;
    utils::check_public_balance(token_contract_address, owner, owner_balance);
    
    // Success case 2: Verify total supply decreases
    utils::check_total_supply(token_contract_address, total_supply);
    
    // Success case 3: Burn on behalf of other with authwit
    let burn_amount_2 = 20_000;
    let burn_call_interface = Token::at(token_contract_address).burn_public(owner, burn_amount_2, random());
    authwit_cheatcodes::add_public_authwit_from_call_interface(owner, recipient, burn_call_interface);
    env.impersonate(recipient);
    burn_call_interface.call(&mut env.public());
    owner_balance -= burn_amount_2;
    total_supply -= burn_amount_2;
    utils::check_public_balance(token_contract_address, owner, owner_balance);
    utils::check_total_supply(token_contract_address, total_supply);
    
    // Failure case 1: Burn more than balance
    // "attempt to subtract with overflow 'public_balances.at(from).read() - amount'"
    env.impersonate(owner);
    let excessive_burn = owner_balance + 100_000;
    let excessive_burn_call = Token::at(token_contract_address).burn_public(owner, excessive_burn, 0);
    env.assert_public_call_fails(excessive_burn_call);
    // Balance should remain unchanged
    utils::check_public_balance(token_contract_address, owner, owner_balance);
    utils::check_total_supply(token_contract_address, total_supply);
    
    // Failure case 2: Burn on behalf of other without authwit
    // "unauthorized"
    let unauthorized_burn = 5_000;
    let unauthorized_burn_call = Token::at(token_contract_address).burn_public(owner, unauthorized_burn, random());
    env.impersonate(recipient);
    env.assert_public_call_fails(unauthorized_burn_call);
    // Balance should remain unchanged
    utils::check_public_balance(token_contract_address, owner, owner_balance);
    utils::check_total_supply(token_contract_address, total_supply);
    
    // Failure case 3: Burn on behalf of other with wrong designated caller
    // "unauthorized"
    let wrong_caller_burn = 3_000;
    let wrong_caller_burn_call = Token::at(token_contract_address).burn_public(owner, wrong_caller_burn, random());
    authwit_cheatcodes::add_public_authwit_from_call_interface(owner, owner, wrong_caller_burn_call);
    env.impersonate(recipient);
    env.assert_public_call_fails(wrong_caller_burn_call);
    // Balance should remain unchanged
    utils::check_public_balance(token_contract_address, owner, owner_balance);
    utils::check_total_supply(token_contract_address, total_supply);
}