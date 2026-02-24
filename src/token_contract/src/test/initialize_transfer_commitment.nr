use crate::test::utils;
use crate::Token;
use aztec::{oracle::random::random, protocol::{address::AztecAddress, traits::FromField}};
use uint_note::PartialUintNote;

#[test]
unconstrained fn initialize_transfer_commitment() {
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    // Transfer tokens
    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    let validity_commitment =
        PartialUintNote::from_field(commitment).compute_validity_commitment(owner);
    assert(
        env.public_context(|context| {
            context.nullifier_exists_unsafe(validity_commitment, token_contract_address)
        }),
        "validity nullifier should exist",
    );
}

#[test(should_fail_with = "Invalid partial note or completer")]
unconstrained fn initialize_transfer_commitment_and_complete_with_incorrect_completer() {
    let (env, token_contract_address, owner, recipient, minter) =
        utils::setup_and_mint_to_private_with_minter(false);

    // Generate an address using a random field
    let random_completer: AztecAddress = AztecAddress::from_field(random());

    // Initialize a transfer commitment using a random completer
    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(
            recipient,
            random_completer,
        ),
    );

    // Using an arbitrary completer should result in a non-existing nullifier
    let validity_commitment =
        PartialUintNote::from_field(commitment).compute_validity_commitment(recipient);
    assert(
        !env.public_context(|context| {
            context.nullifier_exists_unsafe(validity_commitment, token_contract_address)
        }),
        "validity nullifier should not exist",
    );

    // Minting to a commitment uses msg.sender as completer, which is the minter, and not the random completer
    let _ = env.call_public(
        minter,
        Token::at(token_contract_address).mint_to_commitment(commitment, 1 as u128),
    );
}
