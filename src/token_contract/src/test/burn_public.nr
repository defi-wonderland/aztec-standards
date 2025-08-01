use crate::test::utils::{self, mint_amount};
use crate::Token;
use aztec::{oracle::random::random, test::helpers::authwit as authwit_cheatcodes};

#[test]
unconstrained fn burn_public_success() {
    let (env, token_contract_address, owner, _) =
        utils::setup_and_mint_to_public_without_minter(false);
    let burn_amount = mint_amount / 10 as u128;

    // Burn less than balance
    Token::at(token_contract_address).burn_public(owner, burn_amount, 0).call(&mut env.public());
    utils::check_public_balance(token_contract_address, owner, mint_amount - burn_amount);
}

#[test]
unconstrained fn burn_public_decrease_total_supply() {
    let (env, token_contract_address, owner, _) =
        utils::setup_and_mint_to_public_without_minter(false);
    let burn_amount = mint_amount / 10 as u128;

    utils::check_total_supply(token_contract_address, mint_amount);

    // Burn less than balance
    Token::at(token_contract_address).burn_public(owner, burn_amount, 0).call(&mut env.public());
    utils::check_public_balance(token_contract_address, owner, mint_amount - burn_amount);
    utils::check_total_supply(token_contract_address, mint_amount - burn_amount);
}

#[test]
unconstrained fn burn_public_on_behalf_of_other() {
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);
    let burn_amount = mint_amount / 10 as u128;

    // Burn on behalf of other
    let burn_call_interface =
        Token::at(token_contract_address).burn_public(owner, burn_amount, random());
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        recipient,
        burn_call_interface,
    );
    // Impersonate recipient to perform the call
    env.impersonate(recipient);
    // Burn tokens
    burn_call_interface.call(&mut env.public());
    utils::check_public_balance(token_contract_address, owner, mint_amount - burn_amount);
}

#[test(should_fail_with = "attempt to subtract with overflow 'public_balances.at(from).read() - amount'")]
unconstrained fn burn_public_failure_more_than_balance() {
    let (env, token_contract_address, owner, _) =
        utils::setup_and_mint_to_public_without_minter(false);

    // Burn more than balance
    let burn_amount = mint_amount * 10 as u128;
    // Try to burn
    Token::at(token_contract_address).burn_public(owner, burn_amount, 0).call(&mut env.public());
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn burn_public_failure_on_behalf_of_other_without_approval() {
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);

    // Burn on behalf of other without approval
    let burn_amount = mint_amount / 10 as u128;
    let burn_call_interface =
        Token::at(token_contract_address).burn_public(owner, burn_amount, random());
    // Impersonate recipient to perform the call
    env.impersonate(recipient);
    burn_call_interface.call(&mut env.public());
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn burn_public_failure_on_behalf_of_other_wrong_caller() {
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);

    // Burn on behalf of other, wrong designated caller
    let burn_amount = mint_amount / (10 as u128);
    let burn_call_interface =
        Token::at(token_contract_address).burn_public(owner, burn_amount, random());
    authwit_cheatcodes::add_public_authwit_from_call_interface(owner, owner, burn_call_interface);
    // Impersonate recipient to perform the call
    env.impersonate(recipient);
    burn_call_interface.call(&mut env.public());
}
