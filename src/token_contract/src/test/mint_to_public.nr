use crate::{test::utils, Token};
use bignum_field::{bignum_field::BigNumField, bignum_field_note::BigNumFieldNote};

#[test]
unconstrained fn mint_to_public_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, _, minter) =
        utils::setup_with_minter(/* with_account_contracts */ false);

    env.impersonate(minter);
    let mint_amount: BigNumField = BigNumField::new_with_offset(10_000);
    Token::at(token_contract_address).mint_to_public(owner, mint_amount).call(&mut env.public());

    utils::check_public_balance(token_contract_address, owner, mint_amount);

    let total_supply = Token::at(token_contract_address).total_supply().view(&mut env.public());
    assert(total_supply == mint_amount);
}

#[test]
unconstrained fn mint_to_public_failures() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, recipient, minter) =
        utils::setup_with_minter(/* with_account_contracts */ false);

    // As non-minter
    let mint_amount: BigNumField = BigNumField::new_with_offset(10_000);
    env.impersonate(recipient);
    let mint_to_public_call_interface =
        Token::at(token_contract_address).mint_to_public(owner, mint_amount);
    env.assert_public_call_fails(mint_to_public_call_interface);

    utils::check_public_balance(token_contract_address, owner, BigNumField::zero());

    env.impersonate(minter);

    // Overflow recipient

    // We have to do this in 2 steps because we have to pass in a valid BigNumField
    let max_BigNumField = BigNumField::max();
    Token::at(token_contract_address).mint_to_public(recipient, max_BigNumField).call(
        &mut env.public(),
    );

    let mint_to_public_call_interface =
        Token::at(token_contract_address).mint_to_public(owner, BigNumField::one());
    env.assert_public_call_fails(mint_to_public_call_interface);

    utils::check_public_balance(token_contract_address, owner, BigNumField::zero());
    utils::check_total_supply(token_contract_address, max_BigNumField);

    // Overflow total supply
    let mint_to_public_call_interface =
        Token::at(token_contract_address).mint_to_public(owner, max_BigNumField);
    env.assert_public_call_fails(mint_to_public_call_interface);

    utils::check_public_balance(token_contract_address, owner, BigNumField::zero());
}
