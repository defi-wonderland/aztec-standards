use crate::test::utils;
use crate::Token;
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::oracle::random::random;
use uint_note::uint_note::PartialUintNote;

#[test]
unconstrained fn transfer_private_to_public_with_commitment() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, 0 as u128);

    // Transfer tokens
    let transfer_amount = mint_amount;
    env.impersonate(owner);
    let commitment = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check balances
    utils::check_private_balance(token_contract_address, owner, 0 as u128);
    utils::check_public_balance(token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn transfer_private_to_public_with_commitment_stores_commitment() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private_without_minter(false);

    env.impersonate(owner);
    let commitment = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, mint_amount, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    assert(
        utils::_commitment_storage_read(token_contract_address, commitment.commitment()) == true,
        "Commitment not stored",
    );
}

#[test(should_fail_with = "invalid nonce")]
unconstrained fn transfer_private_to_public_with_commitment_and_non_zero_nonce() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, 0 as u128);

    // Transfer tokens
    let transfer_amount = mint_amount;
    env.impersonate(owner);
    Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount, random())
        .call(&mut env.private());
}

#[test]
unconstrained fn transfer_private_to_public_with_commitment_on_behalf_of_other() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private_without_minter(true);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, 0 as u128);

    // Transfer tokens
    let transfer_amount = mint_amount;

    let transfer_private_to_public_commitment_call_interface = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount, 0);

    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_private_to_public_commitment_call_interface,
    );

    // Transfer tokens
    env.impersonate(recipient);
    transfer_private_to_public_commitment_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    // Check balances
    utils::check_private_balance(token_contract_address, owner, 0 as u128);
    utils::check_public_balance(token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn transfer_private_to_public_with_commitment_and_finalize() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, 0 as u128);

    // Transfer tokens
    let transfer_amount = mint_amount;

    env.impersonate(owner);
    let commitment = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount, 0)
        .call(&mut env.private());

    // Before finalize the recipient should have the tokens in public balance
    utils::check_public_balance(token_contract_address, recipient, transfer_amount);

    // Transfer tokens
    env.impersonate(recipient);
    Token::at(token_contract_address)
        .transfer_public_to_commitment(recipient, transfer_amount, commitment, 0)
        .call(&mut env.public());
    env.advance_block_by(1);

    // Check balances
    utils::check_private_balance(token_contract_address, owner, 0 as u128);
    utils::check_public_balance(token_contract_address, recipient, 0 as u128);
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
}

#[test(should_fail_with = "Invalid commitment")]
unconstrained fn transfer_private_to_public_with_commitment_and_finalize_with_invalid_commitment() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, 0 as u128);

    // Transfer tokens
    let transfer_amount = mint_amount;

    env.impersonate(owner);
    // we ignore the returned commitment
    let _ = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount, 0)
        .call(&mut env.private());

    let invalid_commitment = PartialUintNote { commitment: 0xdeadbeef };

    // finalize transfer to an invalid commitment
    env.impersonate(recipient);
    Token::at(token_contract_address)
        .transfer_public_to_commitment(recipient, transfer_amount, invalid_commitment, 0)
        .call(&mut env.public());

    // you can finalize but the recipient will not have tokens
    utils::check_public_balance(token_contract_address, owner, 0 as u128);
    utils::check_private_balance(token_contract_address, owner, 0 as u128);
    utils::check_public_balance(token_contract_address, recipient, 0 as u128);
    utils::check_private_balance(token_contract_address, recipient, 0 as u128);
}

#[test(should_fail_with = "Invalid commitment")]
unconstrained fn transfer_private_to_public_with_commitment_and_finalize_with_commitment_zero() {
    let (env, token_contract_address, owner, recipient, mint_amount) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, 0 as u128);

    // Transfer tokens
    let transfer_amount = mint_amount;

    env.impersonate(owner);
    // we ignore the returned commitment
    let _ = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount, 0)
        .call(&mut env.private());

    let invalid_commitment = PartialUintNote { commitment: 0 };
    // Transfer tokens
    env.impersonate(recipient);
    Token::at(token_contract_address)
        .transfer_public_to_commitment(recipient, transfer_amount, invalid_commitment, 0)
        .call(&mut env.public());

    // check that both owner and recipient have no tokens
    utils::check_public_balance(token_contract_address, owner, 0 as u128);
    utils::check_private_balance(token_contract_address, owner, 0 as u128);
    utils::check_public_balance(token_contract_address, recipient, 0 as u128);
    utils::check_private_balance(token_contract_address, recipient, 0 as u128);
}
