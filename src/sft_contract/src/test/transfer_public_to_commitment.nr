use crate::SFT;
use crate::test::utils;
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test]
unconstrained fn sft_transfer_public_to_commitment_success() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_public(false);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 2);

    env.impersonate(owner);
    let commitment = SFT::at(sft_contract_address)
        .initialize_transfer_commitment(utils::token_id_1, owner, recipient, owner)
        .call(&mut env.private());
    env.advance_block_by(1);

    assert(utils::get_commitment_stored(sft_contract_address, commitment), "Commitment not stored");

    SFT::at(sft_contract_address)
        .transfer_public_to_commitment(owner, utils::token_id_1, commitment, 0)
        .call(&mut env.public());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 1);
}

#[test]
unconstrained fn sft_transfer_public_to_commitment_authorized_success() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_public(true);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 2);

    env.impersonate(owner);
    let commitment = SFT::at(sft_contract_address)
        .initialize_transfer_commitment(utils::token_id_1, owner, recipient, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    assert(utils::get_commitment_stored(sft_contract_address, commitment), "Commitment not stored");

    let transfer_call_interface = SFT::at(sft_contract_address)
        .transfer_public_to_commitment(owner, utils::token_id_1, commitment, 1);

    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        recipient,
        transfer_call_interface,
    );

    env.impersonate(recipient);
    transfer_call_interface.call(&mut env.public());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 1);
}

#[test(should_fail_with = "caller owns no tokens of this type")]
unconstrained fn sft_transfer_public_to_commitment_no_balance_fail() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);

    env.impersonate(owner);
    let commitment = SFT::at(sft_contract_address)
        .initialize_transfer_commitment(utils::token_id_1, owner, recipient, owner)
        .call(&mut env.private());
    env.advance_block_by(1);

    SFT::at(sft_contract_address)
        .transfer_public_to_commitment(owner, utils::token_id_1, commitment, 0)
        .call(&mut env.public());
}

#[test(should_fail_with = "invalid commitment")]
unconstrained fn sft_transfer_public_to_commitment_invalid_commitment_fail() {
    let (env, sft_contract_address, owner, _, _) = utils::setup_and_mint_to_public(false);

    let invalid_commitment = 0xdeadbeef;

    env.impersonate(owner);
    SFT::at(sft_contract_address)
        .transfer_public_to_commitment(owner, utils::token_id_1, invalid_commitment, 0)
        .call(&mut env.public());
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn sft_transfer_public_to_commitment_unauthorized_fail() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_public(true);

    env.impersonate(owner);
    let commitment = SFT::at(sft_contract_address)
        .initialize_transfer_commitment(utils::token_id_1, owner, recipient, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    let transfer_call_interface = SFT::at(sft_contract_address)
        .transfer_public_to_commitment(owner, utils::token_id_1, commitment, 1);

    env.impersonate(recipient);
    transfer_call_interface.call(&mut env.public());
}
