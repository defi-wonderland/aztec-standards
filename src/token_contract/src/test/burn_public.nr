use crate::test::utils::{self, mint_amount};
use crate::Token;
use aztec::{oracle::random::random, test::helpers::authwit as authwit_cheatcodes};

#[test]
unconstrained fn burn_public_success() {
    let (mut env, token_contract_address, owner, _) =
        utils::setup_and_mint_to_public_without_minter(false);
    let burn_amount = mint_amount / 10 as u128;

    // Burn less than balance
    env.call_public(owner, Token::at(token_contract_address).burn_public(owner, burn_amount, 0));
    utils::check_public_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - burn_amount,
    );
}

#[test]
unconstrained fn burn_public_decrease_total_supply() {
    let (mut env, token_contract_address, owner, _) =
        utils::setup_and_mint_to_public_without_minter(false);
    let burn_amount = mint_amount / 10 as u128;

    utils::check_total_supply(env, token_contract_address, mint_amount);

    // Burn less than balance
    env.call_public(owner, Token::at(token_contract_address).burn_public(owner, burn_amount, 0));
    utils::check_public_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - burn_amount,
    );
    utils::check_total_supply(env, token_contract_address, mint_amount - burn_amount);
}

#[test]
unconstrained fn burn_public_on_behalf_of_other() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);
    let burn_amount = mint_amount / 10 as u128;

    // Burn on behalf of other
    let burn_call_interface =
        Token::at(token_contract_address).burn_public(owner, burn_amount, random());
    authwit_cheatcodes::add_public_authwit_from_call(env, owner, recipient, burn_call_interface);
    // Burn tokens
    env.call_public(recipient, burn_call_interface);
    utils::check_public_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - burn_amount,
    );
}

#[test(should_fail_with = "attempt to subtract with overflow 'self.storage.public_balances.at(from).read() - amount'")]
unconstrained fn burn_public_failure_more_than_balance() {
    let (mut env, token_contract_address, owner, _) =
        utils::setup_and_mint_to_public_without_minter(false);

    // Burn more than balance
    let burn_amount = mint_amount * 10 as u128;
    // Try to burn
    env.call_public(owner, Token::at(token_contract_address).burn_public(owner, burn_amount, 0));
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn burn_public_failure_on_behalf_of_other_without_approval() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);

    // Burn on behalf of other without approval
    let burn_amount = mint_amount / 10 as u128;
    let burn_call_interface =
        Token::at(token_contract_address).burn_public(owner, burn_amount, random());
    env.call_public(recipient, burn_call_interface);
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn burn_public_failure_on_behalf_of_other_wrong_caller() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);

    // Burn on behalf of other, wrong designated caller
    let burn_amount = mint_amount / (10 as u128);
    let burn_call_interface =
        Token::at(token_contract_address).burn_public(owner, burn_amount, random());
    authwit_cheatcodes::add_public_authwit_from_call(env, owner, owner, burn_call_interface);
    env.call_public(recipient, burn_call_interface);
}
