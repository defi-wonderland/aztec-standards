use crate::test::utils;
use crate::Token;
use aztec::{oracle::random::random, prelude::AztecAddress, protocol_types::traits::FromField};
use uint_note::uint_note::PartialUintNote;

#[test]
unconstrained fn test_initialize_transfer_commitment() {
    // Setup once with minter
    let (env, token_contract_address, owner, recipient, minter) = utils::setup_with_minter(false);

    // Mint a large amount once for all tests
    let initial_mint_amount: u128 = 1_000_000;
    env.impersonate(minter);
    Token::at(token_contract_address).mint_to_private(owner, owner, initial_mint_amount).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Success case: Initialize transfer commitment with correct completer
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

    // Failure case: Initialize transfer commitment with incorrect completer
    // "Invalid partial note or completer"
    // Generate an address using a random field
    let random_completer: AztecAddress = AztecAddress::from_field(random());

    // Initialize a transfer commitment using a random completer
    env.impersonate(owner);
    let commitment_2 = Token::at(token_contract_address)
        .initialize_transfer_commitment(owner, recipient, random_completer)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Using an arbitrary completer should result in a non-existing nullifier
    let validity_commitment_2 =
        PartialUintNote { commitment: commitment_2 }.compute_validity_commitment(recipient);
    assert(
        !env.public().nullifier_exists(validity_commitment_2, token_contract_address),
        "validity nullifier should not exist",
    );

    // Minting to a commitment uses msg.sender as completer, which is the minter, and not the random completer
    env.impersonate(minter);
    let mint_to_commitment_call =
        Token::at(token_contract_address).mint_to_commitment(commitment_2, 1 as u128);
    env.assert_public_call_fails(mint_to_commitment_call);
}
