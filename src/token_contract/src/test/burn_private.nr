use crate::test::utils;
use crate::Token;
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::oracle::random::random;

#[test]
unconstrained fn test_burn_private() {
    // Setup once with account contracts since we need authwit
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(true);
    // minter is already extracted from setup_with_minter

    // Mint a large amount once for all tests
    let initial_mint_amount: u128 = 1_000_000;
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_private(owner, owner, initial_mint_amount).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Track balance throughout tests
    let mut owner_balance = initial_mint_amount;
    utils::check_private_balance(token_contract_address, owner, owner_balance);

    // Success case 1: Burn on behalf of self (less than balance)
    env.impersonate(owner);
    let burn_amount_1 = 10_000;
    Token::at(token_contract_address).burn_private(owner, burn_amount_1, 0).call(&mut env.private());
    owner_balance -= burn_amount_1;
    utils::check_private_balance(token_contract_address, owner, owner_balance);

    // Success case 2: Burn on behalf of other with authwit
    let burn_amount_2 = 20_000;
    let burn_call_interface =
        Token::at(token_contract_address).burn_private(owner, burn_amount_2, random());
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        burn_call_interface,
    );
    env.impersonate(recipient);
    burn_call_interface.call(&mut env.private());
    owner_balance -= burn_amount_2;
    utils::check_private_balance(token_contract_address, owner, owner_balance);

    // Failure case 1: Burn more than balance
    // "Balance too low"
    env.impersonate(owner);
    let excessive_burn = owner_balance + 100_000;
    let excessive_burn_call =
        Token::at(token_contract_address).burn_private(owner, excessive_burn, 0);
    env.assert_private_call_fails(excessive_burn_call);
    // Balance should remain unchanged
    utils::check_private_balance(token_contract_address, owner, owner_balance);

    // Failure case 2: Burn on behalf of other more than balance (with authwit)
    // "Balance too low"
    let excessive_burn_2 = owner_balance + 50_000;
    let excessive_burn_call_2 =
        Token::at(token_contract_address).burn_private(owner, excessive_burn_2, random());
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        excessive_burn_call_2,
    );
    env.impersonate(recipient);
    env.assert_private_call_fails(excessive_burn_call_2);
    // Balance should remain unchanged
    utils::check_private_balance(token_contract_address, owner, owner_balance);

    // Failure case 3: Burn on behalf of other without authwit
    // "Unknown auth witness for message hash"
    let unauthorized_burn = 5_000;
    let unauthorized_burn_call =
        Token::at(token_contract_address).burn_private(owner, unauthorized_burn, 3);
    env.impersonate(recipient);
    env.assert_private_call_fails(unauthorized_burn_call);
    // Balance should remain unchanged
    utils::check_private_balance(token_contract_address, owner, owner_balance);

    // Failure case 4: Burn on behalf of other with wrong designated caller
    // "Unknown auth witness for message hash"
    let wrong_caller_burn = 3_000;
    let wrong_caller_burn_call =
        Token::at(token_contract_address).burn_private(owner, wrong_caller_burn, 3);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        owner,
        wrong_caller_burn_call,
    );
    env.impersonate(recipient);
    env.assert_private_call_fails(wrong_caller_burn_call);
    // Balance should remain unchanged
    utils::check_private_balance(token_contract_address, owner, owner_balance);
}
