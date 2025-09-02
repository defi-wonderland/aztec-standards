use crate::Escrow;
use crate::test::utils as escrow_utils;
use aztec::oracle::get_contract_instance::get_contract_instance;
use aztec::prelude::AztecAddress;
use aztec::protocol_types::traits::FromField;
use token::{test::utils as token_utils, Token};

#[test]
unconstrained fn escrow_withdraw_success() {
    let escrow_secret: Field = 123456;
    let (env, escrow_contract_address, token_contract_address, _, _, recipient, minter) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    let escrow_instance = get_contract_instance(escrow_contract_address);
    let logic_contract_address = AztecAddress::from_field(escrow_instance.salt);

    // Mint some tokens to escrow
    let amount: u128 = token_utils::mint_amount;
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_private(minter, escrow_contract_address, amount).call(
        &mut env.private(),
    );
    env.advance_block_by(1);
    // Check the escrow received and can read the tokens
    token_utils::check_private_balance(token_contract_address, escrow_contract_address, amount);

    env.impersonate(logic_contract_address);
    Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Check recipient got tokens
    token_utils::check_private_balance(token_contract_address, recipient, amount);
}

#[test]
unconstrained fn escrow_withdraw_twice_success() {
    let escrow_secret: Field = 123456;
    let (env, escrow_contract_address, token_contract_address, _, _, recipient, minter) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    let escrow_instance = get_contract_instance(escrow_contract_address);
    let logic_contract_address = AztecAddress::from_field(escrow_instance.salt);

    // Mint some tokens to escrow
    let total_amount: u128 = token_utils::mint_amount * 2;
    env.impersonate(minter);
    Token::at(token_contract_address)
        .mint_to_private(minter, escrow_contract_address, total_amount)
        .call(&mut env.private());
    env.advance_block_by(1);
    // Check the escrow received and can read the tokens
    token_utils::check_private_balance(
        token_contract_address,
        escrow_contract_address,
        total_amount,
    );

    let amount: u128 = token_utils::mint_amount;
    // Partial withdrawal
    env.impersonate(logic_contract_address);
    Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Check balances
    token_utils::check_private_balance(token_contract_address, recipient, amount);
    token_utils::check_private_balance(token_contract_address, escrow_contract_address, amount);

    // Complete withdrawal
    env.impersonate(logic_contract_address);
    Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Check balances
    token_utils::check_private_balance(token_contract_address, recipient, total_amount);
    token_utils::check_private_balance(token_contract_address, escrow_contract_address, 0);
}

#[test(should_fail_with = "Not Authorized")]
unconstrained fn escrow_withdraw_unauthorized() {
    let escrow_secret: Field = 123456;
    let (env, escrow_contract_address, token_contract_address, _, owner, recipient, _) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    let escrow_instance = get_contract_instance(escrow_contract_address);
    let logic_contract_address = AztecAddress::from_field(escrow_instance.salt);

    let amount: u128 = token_utils::mint_amount;
    env.impersonate(owner);
    Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient).call(
        &mut env.private(),
    );
    env.advance_block_by(1);
}
