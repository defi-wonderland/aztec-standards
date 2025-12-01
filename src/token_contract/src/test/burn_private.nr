use crate::test::utils::{self, mint_amount};
use crate::Token;
use aztec::{oracle::random::random, test::helpers::authwit as authwit_cheatcodes};

#[test]
unconstrained fn burn_private_on_behalf_of_self() {
    let (env, token_contract_address, owner, _) =
        utils::setup_and_mint_to_private_without_minter(false);
    let burn_amount = mint_amount / 10;

    // Burn less than balance
    env.call_private(owner, Token::at(token_contract_address).burn_private(owner, burn_amount, 0));
    utils::check_private_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - burn_amount,
    );
}

#[test]
unconstrained fn burn_private_on_behalf_of_other() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(true);
    let burn_amount = mint_amount / 10;

    // Burn on behalf of other
    let burn_call_interface =
        Token::at(token_contract_address).burn_private(owner, burn_amount, random());
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, recipient, burn_call_interface);
    // Burn tokens
    env.call_private(recipient, burn_call_interface);
    utils::check_private_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - burn_amount,
    );
}

#[test(should_fail_with = "Balance too low")]
unconstrained fn burn_private_failure_more_than_balance() {
    let (mut env, token_contract_address, owner, _) =
        utils::setup_and_mint_to_public_without_minter(false);

    // Burn more than balance
    let burn_amount = mint_amount * 10;
    env.call_private(owner, Token::at(token_contract_address).burn_private(owner, burn_amount, 0));
}

#[test(should_fail_with = "Balance too low")]
unconstrained fn burn_private_failure_on_behalf_of_other_more_than_balance() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);

    // Burn more than balance
    let burn_amount = mint_amount * (10 as u128);
    // Burn on behalf of other
    let burn_call_interface =
        Token::at(token_contract_address).burn_private(owner, burn_amount, random());
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, recipient, burn_call_interface);
    env.call_private(recipient, burn_call_interface);
}
#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn burn_private_failure_on_behalf_of_other_without_approval() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);

    // // Burn more than balance
    let burn_amount = mint_amount / (10 as u128);
    // // Burn on behalf of other
    let burn_call_interface =
        Token::at(token_contract_address).burn_private(owner, burn_amount, random());
    env.call_private(recipient, burn_call_interface);
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn burn_private_failure_on_behalf_of_other_wrong_designated_caller() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);

    // Burn more than balance
    let burn_amount = mint_amount / (10 as u128);
    // Burn on behalf of other
    let burn_call_interface =
        Token::at(token_contract_address).burn_private(owner, burn_amount, random());
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, owner, burn_call_interface);
    env.call_private(recipient, burn_call_interface);
}
