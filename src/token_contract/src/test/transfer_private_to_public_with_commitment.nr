use crate::test::utils::{self, mint_amount};
use crate::Token;
use aztec::protocol_types::traits::FromField;
use aztec::test::helpers::authwit as authwit_cheatcodes;
use uint_note::uint_note::PartialUintNote;

#[test]
unconstrained fn transfer_private_to_public_with_commitment() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(env, token_contract_address, owner, mint_amount);
    utils::check_private_balance(env, token_contract_address, recipient, 0 as u128);

    // Transfer tokens
    let transfer_amount = mint_amount;
    let _ = env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    // Check balances
    utils::check_private_balance(env, token_contract_address, owner, 0 as u128);
    utils::check_public_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn transfer_private_to_public_with_commitment_emits_validity_nullifier() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            mint_amount,
            0,
        ),
    );

    // The caller is the completer of the partial note.
    let validity_commitment =
        PartialUintNote::from_field(commitment).compute_validity_commitment(owner);
    assert(
        env.public_context(|context| {
            context.nullifier_exists(validity_commitment, token_contract_address)
        }),
        "validity nullifier should exist",
    );
}

#[test]
unconstrained fn transfer_private_to_public_with_commitment_on_behalf_of_other() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(true);

    utils::check_private_balance(env, token_contract_address, owner, mint_amount);
    utils::check_private_balance(env, token_contract_address, recipient, 0 as u128);

    // Transfer tokens
    let transfer_amount = mint_amount;

    let transfer_private_to_public_commitment_call_interface = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount, 0);

    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        owner,
        recipient,
        transfer_private_to_public_commitment_call_interface,
    );

    // Transfer tokens
    let _ = env.call_private(recipient, transfer_private_to_public_commitment_call_interface);

    // Check balances
    utils::check_private_balance(env, token_contract_address, owner, 0 as u128);
    utils::check_public_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn transfer_private_to_public_with_commitment_and_finalize() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(env, token_contract_address, owner, mint_amount);
    utils::check_private_balance(env, token_contract_address, recipient, 0 as u128);

    // Transfer tokens
    let transfer_amount = mint_amount;

    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    // Before finalize the recipient should have the tokens in public balance
    utils::check_public_balance(env, token_contract_address, recipient, transfer_amount);

    let action = Token::at(token_contract_address).transfer_public_to_commitment(
        recipient,
        commitment,
        transfer_amount,
        0,
    );
    authwit_cheatcodes::add_public_authwit_from_call(env, recipient, owner, action);
    let _ = env.call_public(owner, action);

    // Check balances
    utils::check_private_balance(env, token_contract_address, owner, 0 as u128);
    utils::check_public_balance(env, token_contract_address, recipient, 0 as u128);
    utils::check_private_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test(should_fail_with = "Invalid partial note or completer")]
unconstrained fn transfer_private_to_public_with_commitment_and_finalize_with_invalid_commitment() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(env, token_contract_address, owner, mint_amount);
    utils::check_private_balance(env, token_contract_address, recipient, 0 as u128);

    // Transfer tokens
    let transfer_amount = mint_amount;

    // we ignore the returned commitment
    let _ = env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    let invalid_commitment = 0xdeadbeef;

    // finalize transfer to an invalid commitment
    env.call_public(
        recipient,
        Token::at(token_contract_address).transfer_public_to_commitment(
            recipient,
            invalid_commitment,
            transfer_amount,
            0,
        ),
    );

    // you can finalize but the recipient will not have tokens
    utils::check_public_balance(env, token_contract_address, owner, 0 as u128);
    utils::check_private_balance(env, token_contract_address, owner, 0 as u128);
    utils::check_public_balance(env, token_contract_address, recipient, 0 as u128);
    utils::check_private_balance(env, token_contract_address, recipient, 0 as u128);
}

#[test(should_fail_with = "Invalid partial note or completer")]
unconstrained fn transfer_private_to_public_with_commitment_and_finalize_with_commitment_zero() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(env, token_contract_address, owner, mint_amount);
    utils::check_private_balance(env, token_contract_address, recipient, 0 as u128);

    // Transfer tokens
    let transfer_amount = mint_amount;

    // we ignore the returned commitment
    let _ = env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    let invalid_commitment = 0;
    // Transfer tokens
    env.call_public(
        recipient,
        Token::at(token_contract_address).transfer_public_to_commitment(
            recipient,
            invalid_commitment,
            transfer_amount,
            0,
        ),
    );

    // check that both owner and recipient have no tokens
    utils::check_public_balance(env, token_contract_address, owner, 0 as u128);
    utils::check_private_balance(env, token_contract_address, owner, 0 as u128);
    utils::check_public_balance(env, token_contract_address, recipient, 0 as u128);
    utils::check_private_balance(env, token_contract_address, recipient, 0 as u128);
}
