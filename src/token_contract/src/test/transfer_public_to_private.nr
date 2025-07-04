use crate::{test::utils, Token};
use authwit::cheatcodes as authwit_cheatcodes;

#[test]
unconstrained fn test_transfer_public_to_private_all_cases() {
    // Setup with large initial mint for all test cases
    let initial_mint = 1_000_000;

    // Test 1: Basic transfer success
    let (env, token_contract_address, sender, recipient) =
        utils::setup_with_initial_supply(false, initial_mint);

    utils::check_public_balance(token_contract_address, sender, initial_mint);
    utils::check_private_balance(token_contract_address, recipient, 0);

    let nonce = 0;
    let transfer_amount = 200_000;

    env.impersonate(sender);
    Token::at(token_contract_address)
        .transfer_public_to_private(sender, recipient, transfer_amount, nonce)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check balances after transfer
    utils::check_public_balance(
        token_contract_address,
        sender,
        initial_mint - transfer_amount,
    );
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);

    // Test 2: Not enough balance failure
    let transfer_amount_too_big = initial_mint * 2;

    // Expected error: Assertion failed: attempt to subtract with overflow 'public_balances.at(from).read() - amount'
    env.assert_private_call_fails(Token::at(token_contract_address).transfer_public_to_private(
        sender,
        recipient,
        transfer_amount_too_big,
        nonce,
    ));

    // Test 3: Authwitness success (need account contracts)
    let (env2, token_contract_address2, sender2, recipient2) =
        utils::setup_with_initial_supply(true, initial_mint);

    let transfer_amount2 = 300_000;

    env2.impersonate(sender2);
    let transfer_public_to_private_call_interface = Token::at(token_contract_address2)
        .transfer_public_to_private(sender2, recipient2, transfer_amount2, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        sender2,
        recipient2,
        transfer_public_to_private_call_interface,
    );

    env2.impersonate(recipient2);
    transfer_public_to_private_call_interface.call(&mut env2.private());
    env2.advance_block_by(1);

    // Check balances after authwit transfer
    utils::check_private_balance(token_contract_address2, recipient2, transfer_amount2);
    utils::check_public_balance(
        token_contract_address2,
        sender2,
        initial_mint - transfer_amount2,
    );

    // Test 4: Authwitness unauthorized failure
    let transfer_amount3 = 100_000;

    env2.impersonate(sender2);
    let transfer_public_to_private_call_interface_fail = Token::at(token_contract_address2)
        .transfer_public_to_private(sender2, recipient2, transfer_amount3, 1);

    // No authwit added for this call

    env2.impersonate(recipient2);

    // Expected error: Unknown auth witness for message hash
    env2.assert_private_call_fails(transfer_public_to_private_call_interface_fail);
}
