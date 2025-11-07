use crate::{test::utils::{self, mint_amount}, Token};
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test]
unconstrained fn transfer_public_to_private_success() {
    let (mut env, token_contract_address, sender, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);

    utils::check_public_balance(env, token_contract_address, sender, mint_amount);
    utils::check_private_balance(env, token_contract_address, recipient, 0);

    let nonce = 0;
    let transfer_amount = mint_amount / 2;

    env.call_private(
        sender,
        Token::at(token_contract_address).transfer_public_to_private(
            sender,
            recipient,
            transfer_amount,
            nonce,
        ),
    );

    // sender public balance decreases
    utils::check_public_balance(env, token_contract_address, sender, transfer_amount);
    assert(
        env.view_public(Token::at(token_contract_address).balance_of_public(sender))
            == transfer_amount,
        "public balance is not correct",
    );
    // recipient private balance incre ases
    utils::check_private_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test(should_fail_with = "Assertion failed: attempt to subtract with overflow 'public_balances.at(from).read() - amount'")]
unconstrained fn transfer_public_to_private_not_enough_balance() {
    let (mut env, token_contract_address, sender, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);

    utils::check_public_balance(env, token_contract_address, sender, mint_amount);
    utils::check_private_balance(env, token_contract_address, recipient, 0);

    let nonce = 0;
    let transfer_amount = mint_amount * 2;

    env.call_private(
        sender,
        Token::at(token_contract_address).transfer_public_to_private(
            sender,
            recipient,
            transfer_amount,
            nonce,
        ),
    );
}

#[test]
unconstrained fn transfer_public_to_private_authwitness_success() {
    let (mut env, token_contract_address, sender, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);

    let transfer_amount = mint_amount / 2;

    let transfer_public_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_private(sender, recipient, transfer_amount, 0);
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        env,
        sender,
        recipient,
        transfer_public_to_private_call_interface,
    );

    env.call_private(recipient, transfer_public_to_private_call_interface);

    // Check balances changes as expected
    utils::check_private_balance(env, token_contract_address, recipient, transfer_amount);
    utils::check_public_balance(env, token_contract_address, sender, transfer_amount);
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn transfer_public_to_private_authwitness_unauthorized() {
    let (mut env, token_contract_address, sender, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);

    let transfer_amount = mint_amount / 2;

    let transfer_public_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_private(sender, recipient, transfer_amount, 0);

    // no authwit added

    env.call_private(recipient, transfer_public_to_private_call_interface);
}
