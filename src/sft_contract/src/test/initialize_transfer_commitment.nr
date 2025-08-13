use crate::SFT;
use crate::test::utils;

#[test]
unconstrained fn sft_initialize_transfer_commitment_success() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_private(false);

    env.impersonate(owner);
    let commitment = SFT::at(sft_contract_address)
        .initialize_transfer_commitment(utils::token_id_1, owner, recipient, owner)
        .call(&mut env.private());
    env.advance_block_by(1);

    assert(utils::get_commitment_stored(sft_contract_address, commitment), "Commitment not stored");
}

#[test]
unconstrained fn sft_initialize_transfer_commitment_by_recipient_success() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_private(false);

    env.impersonate(recipient);
    let commitment = SFT::at(sft_contract_address)
        .initialize_transfer_commitment(utils::token_id_1, owner, recipient, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    assert(utils::get_commitment_stored(sft_contract_address, commitment), "Commitment not stored");
}

#[test]
unconstrained fn sft_initialize_transfer_commitment_self_success() {
    let (env, sft_contract_address, owner, _, _) = utils::setup_and_mint_to_private(false);

    env.impersonate(owner);
    let commitment = SFT::at(sft_contract_address)
        .initialize_transfer_commitment(utils::token_id_1, owner, owner, owner)
        .call(&mut env.private());
    env.advance_block_by(1);

    assert(utils::get_commitment_stored(sft_contract_address, commitment), "Commitment not stored");
}

#[test]
unconstrained fn sft_initialize_transfer_commitment_by_third_party_success() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_and_mint_to_private(false);

    env.impersonate(minter);
    let commitment = SFT::at(sft_contract_address)
        .initialize_transfer_commitment(utils::token_id_1, owner, recipient, minter)
        .call(&mut env.private());
    env.advance_block_by(1);

    assert(utils::get_commitment_stored(sft_contract_address, commitment), "Commitment not stored");
}
