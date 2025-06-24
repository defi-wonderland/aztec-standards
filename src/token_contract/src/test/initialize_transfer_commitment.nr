use crate::test::utils;
use crate::Token;
use uint_note::uint_note::PartialUintNote;
use aztec::prelude::AztecAddress;
use aztec::protocol_types::traits::FromField;

#[test]
unconstrained fn initialize_transfer_commitment() {
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    // Transfer tokens
    env.impersonate(owner);
    let commitment = Token::at(token_contract_address)
        .initialize_transfer_commitment(owner, recipient, owner)
        .call(&mut env.private());
    env.advance_block_by(1);

    let validity_commitment = PartialUintNote { commitment }.compute_validity_commitment(owner);
    assert(
        env.public().nullifier_exists(validity_commitment, token_contract_address),
        "validity nullifier should exist",
    );
}


#[test]
unconstrained fn initialize_transfer_commitment_and_complete_with_incorrect_completer() {
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    // Transfer tokens
    env.impersonate(owner);
    let commitment = Token::at(token_contract_address)
        .initialize_transfer_commitment(owner, recipient, owner)
        .call(&mut env.private());
    env.advance_block_by(1);

    let invalid_completer: AztecAddress = AztecAddress::from_field(0xdead);

    // Using an invalid completer should result in a non-existing nullifier
    let validity_commitment = PartialUintNote { commitment }.compute_validity_commitment(invalid_completer);
    assert(
        !env.public().nullifier_exists(validity_commitment, token_contract_address),
        "validity nullifier should not exist",
    );

    // Minting to a commitment with an invalid completer should fail
    let mint_to_commitment_call_interface =
        Token::at(token_contract_address).mint_to_commitment(commitment, 1 as u128);
    env.assert_public_call_fails(mint_to_commitment_call_interface);
}