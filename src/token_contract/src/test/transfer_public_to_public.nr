use crate::test::utils;
use crate::Token;
use authwit::cheatcodes as authwit_cheatcodes;

#[test]
unconstrained fn test_transfer_public_to_public_all_cases() {
    // Setup with large initial mint for all test cases
    let initial_mint = 1_000_000;

    // Test 1: Basic public transfer
    let (env, token_contract_address, owner, recipient) =
        utils::setup_with_initial_supply(true, initial_mint);

    let mut owner_balance = initial_mint;
    let mut recipient_balance = 0;

    let transfer_amount = 100_000;
    Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount, 0)
        .call(&mut env.public());
    owner_balance -= transfer_amount;
    recipient_balance += transfer_amount;
    // Check balances
    utils::check_public_balance(token_contract_address, owner, owner_balance);
    utils::check_public_balance(token_contract_address, recipient, recipient_balance);

    // Test 2: Transfer to self
    let transfer_to_self_amount = 50_000;
    Token::at(token_contract_address)
        .transfer_public_to_public(owner, owner, transfer_to_self_amount, 0)
        .call(&mut env.public());

    // Balance should remain the same after self-transfer
    utils::check_public_balance(token_contract_address, owner, owner_balance);

    // Test 3: Transfer more than balance failure
    let transfer_too_much = initial_mint + 1;

    // Expected error: attempt to subtract with overflow 'public_balances.at(from).read() - amount'
    env.assert_public_call_fails(Token::at(token_contract_address).transfer_public_to_public(
        owner,
        recipient,
        transfer_too_much,
        0,
    ));

    // Test 4: Transfer on behalf of other with authwit (need account contracts)
    let transfer_amount2 = 150_000;
    let public_transfer_call_interface = Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount2, 1);
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        recipient,
        public_transfer_call_interface,
    );

    env.impersonate(recipient);
    public_transfer_call_interface.call(&mut env.public());
    owner_balance -= transfer_amount2;
    recipient_balance += transfer_amount2;

    // Check balances after authwit transfer
    utils::check_public_balance(token_contract_address, owner, owner_balance);
    utils::check_public_balance(token_contract_address, recipient, recipient_balance);

    // Test 5: Transfer on behalf without approval failure
    let transfer_amount3 = 75_000;
    let public_transfer_no_authwit = Token::at(token_contract_address).transfer_public_to_public(
        owner,
        recipient,
        transfer_amount3,
        2,
    );

    env.impersonate(recipient);

    // Expected error: unauthorized
    env.assert_public_call_fails(public_transfer_no_authwit);

    // Test 6: Transfer on behalf with authwit but more than balance
    let transfer_too_much2 = initial_mint + 1;
    let public_transfer_too_much = Token::at(token_contract_address).transfer_public_to_public(
        owner,
        recipient,
        transfer_too_much2,
        3,
    );
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        recipient,
        public_transfer_too_much,
    );

    env.impersonate(recipient);

    // Expected error: attempt to subtract with overflow 'public_balances.at(from).read() - amount'
    env.assert_public_call_fails(public_transfer_too_much);

    // Test 7: Transfer with authwit to wrong caller
    let third_party = env.create_account_contract(3);
    let transfer_amount4 = 25_000;
    let public_transfer_wrong_caller = Token::at(token_contract_address).transfer_public_to_public(
        owner,
        third_party,
        transfer_amount4,
        4,
    );
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        owner, // Wrong! Should be third_party
        public_transfer_wrong_caller,
    );

    env.impersonate(third_party);

    // Expected error: unauthorized
    env.assert_public_call_fails(public_transfer_wrong_caller);
}
