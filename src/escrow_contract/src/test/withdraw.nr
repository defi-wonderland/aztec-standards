use crate::Escrow;
use crate::test::utils as escrow_utils;
use aztec::oracle::get_contract_instance::get_contract_instance;
use aztec::prelude::AztecAddress;
use aztec::protocol_types::traits::FromField;
use token::{test::utils as token_utils, Token};

#[test]
unconstrained fn escrow_withdraw_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (_, token_contract_address, _, recipient, minter) = token_utils::setup_with_minter(false);

    let escrow_secret: Field = 123456;
    let (env, escrow_contract_address) = escrow_utils::deploy_escrow(escrow_secret);

    let escrow_instance = get_contract_instance(escrow_contract_address);
    let logic_contract_address = AztecAddress::from_field(escrow_instance.salt);

    // Mint some tokens to escrow
    let amount: u128 = token_utils::mint_amount;
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_private(minter, escrow_contract_address, amount).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    env.impersonate(logic_contract_address);
    Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient).call(
        &mut env.private(),
    );
    env.advance_block_by(1);
}

#[test(should_fail_with = "Not Authorized")]
unconstrained fn escrow_withdraw_unauthorized() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (_, token_contract_address, owner, recipient, minter) =
        token_utils::setup_with_minter(false);

    let escrow_secret: Field = 123456;
    let (env, escrow_contract_address) = escrow_utils::deploy_escrow(escrow_secret);

    let escrow_instance = get_contract_instance(escrow_contract_address);
    let logic_contract_address = AztecAddress::from_field(escrow_instance.salt);

    let amount: u128 = token_utils::mint_amount;
    env.impersonate(owner);
    Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Check recipient got shares
    // token_utils::check_private_balance(token_contract_address, recipient, shares);
    // token_utils::check_public_balance(token_contract_address, recipient, 0);

    // // Check the total supply got updated
    // let total_supply = Token::at(token_contract_address).total_supply().view(&mut env.public());
    // assert(total_supply == shares, "Incorrect shares total supply");

    // // Check vault has assets
    // token_utils::check_public_balance(token_contract_address, vault_address, deposit_amount);
}
