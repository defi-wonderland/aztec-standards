use crate::test::utils as escrow_utils;
use token_contract::{Token, test::utils as token_utils};
use aztec::oracle::get_contract_instance::get_contract_instance;
use aztec::prelude::AztecAddress;

#[test]
unconstrained fn withdraw_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (_, token_contract_address, _, recipient, minter) = utils::setup_with_minter(false);

    let escrow_secret: Field = 123456;
    let (env, escrow_contract_address) = escrow_utils::deploy_escrow(escrow_secret);

    let contract_instance = get_contract_instance(escrow_contract_address);
    let logic_contract_address = contract_instance.salt as AztecAddress;

    env.impersonate(logic_contract_address);
    Token::at(escrow_contract_address)
        .withdraw(token_contract_address, mint_amount, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);
}

#[test(should_fail_with = "Not Authorized")]
unconstrained fn withdraw_unauthorized() {

    // // Mint some asset tokens to owner
    // let deposit_amount: u128 = mint_amount;
    // env.impersonate(owner);
    // Token::at(asset_address).mint_to_private(owner, owner, deposit_amount).call(&mut env.private());
    // env.advance_block_by(1);


    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (_, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);

    let escrow_secret: Field = 123456;
    let (env, escrow_contract_address) = escrow_utils::deploy_escrow(escrow_secret);

    let contract_instance = get_contract_instance(escrow_contract_address);
    let logic_contract_address = contract_instance.salt as AztecAddress;

    env.impersonate(owner);
    Token::at(escrow_contract_address)
        .withdraw(token_contract_address, mint_amount, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);


    // Check recipient got shares
    // utils::check_private_balance(vault_address, recipient, shares);
    // utils::check_public_balance(vault_address, recipient, 0);

    // // Check the total supply got updated
    // let total_supply = Token::at(vault_address).total_supply().view(&mut env.public());
    // assert(total_supply == shares, "Incorrect shares total supply");

    // // Check vault has assets
    // utils::check_public_balance(asset_address, vault_address, deposit_amount);
}
