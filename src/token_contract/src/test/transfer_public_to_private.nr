use crate::{test::utils, Token};
use authwit::cheatcodes as authwit_cheatcodes;

#[test]
unconstrained fn test_transfer_public_to_private_all_cases() {
    // Setup with large initial mint for all test cases
    let initial_mint = 2_000_000;

    // Test 1: Basic transfer success
    let (env, token_contract_address, sender, recipient) =
        utils::setup_with_initial_supply(true, initial_mint);

    utils::check_public_balance(token_contract_address, sender, initial_mint);
    utils::check_private_balance(token_contract_address, recipient, 0);

    let mut sender_balance = initial_mint;
    let mut recipient_balance = 0;

    let nonce = 0;
    let transfer_amount = 200_000;

    env.impersonate(sender);
    Token::at(token_contract_address)
        .transfer_public_to_private(sender, recipient, transfer_amount, nonce)
        .call(&mut env.private());
    env.advance_block_by(1);

    sender_balance -= transfer_amount;
    recipient_balance += transfer_amount;
    // Check balances after transfer
    utils::check_public_balance(token_contract_address, sender, sender_balance);
    utils::check_private_balance(token_contract_address, recipient, recipient_balance);

    // Test 2: Not enough balance failure
    let transfer_amount_too_big = initial_mint * 2;

    // Expected error: Assertion failed: attempt to subtract with overflow 'public_balances.at(from).read() - amount'
    env.assert_private_call_fails(Token::at(token_contract_address).transfer_public_to_private(
        sender,
        recipient,
        transfer_amount_too_big,
        nonce,
    ));

    // Test 3: Authwitness success
    let transfer_amount2 = 300_000;
    env.impersonate(sender);
    let transfer_public_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_private(sender, recipient, transfer_amount2, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        sender,
        recipient,
        transfer_public_to_private_call_interface,
    );

    env.impersonate(recipient);
    transfer_public_to_private_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    sender_balance -= transfer_amount2;
    recipient_balance += transfer_amount2;

    // Check balances after authwit transfer
    utils::check_private_balance(token_contract_address, recipient, recipient_balance);
    utils::check_public_balance(token_contract_address, sender, sender_balance);

    // Test 4: Authwitness unauthorized failure
    let transfer_amount3 = 100_000;

    env.impersonate(sender);
    let transfer_public_to_private_call_interface_fail = Token::at(token_contract_address)
        .transfer_public_to_private(sender, recipient, transfer_amount3, 1);

    // No authwit added for this call

    env.impersonate(recipient);

    // Expected error: Unknown auth witness for message hash
    env.assert_private_call_fails(transfer_public_to_private_call_interface_fail);
}
