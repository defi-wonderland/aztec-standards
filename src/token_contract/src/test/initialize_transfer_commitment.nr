use crate::test::utils;
use crate::Token;
use uint_note::uint_note::PartialUintNote;

#[test]
unconstrained fn initialize_transfer_commitment() {
    let (env, token_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_private_without_minter(false);

    // Transfer tokens
    env.impersonate(owner);
    let commitment = Token::at(token_contract_address)
        .initialize_transfer_commitment(owner, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    let validity_commitment = PartialUintNote { commitment }.compute_validity_commitment(owner);
    assert(
        env.public().nullifier_exists(validity_commitment, token_contract_address),
        "validity nullifier should exist",
    );
}
