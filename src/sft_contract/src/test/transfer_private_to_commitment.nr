use crate::SFT;
use crate::test::utils;
use aztec::test::helpers::authwit as authwit_cheatcodes;

/// Test successful private to commitment transfer
#[test]
unconstrained fn sft_transfer_private_to_commitment_success() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_private(false);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 2);

    env.impersonate(owner);
    let commitment: Field = SFT::at(sft_contract_address).initialize_transfer_commitment(utils::token_id_1, owner, recipient, owner).call(&mut env.private());
    env.advance_block_by(1);

    assert(utils::get_commitment_stored(sft_contract_address, commitment), "Commitment not stored");

    SFT::at(sft_contract_address).transfer_private_to_commitment(owner, utils::token_id_1, commitment, 0).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 1);
    assert(utils::get_commitment_stored(sft_contract_address, commitment), "Commitment not stored after transfer");
}

/// Test successful authorized transfer to commitment
#[test]
unconstrained fn sft_transfer_private_to_commitment_authorized_success() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_private(true);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 2);

    env.impersonate(owner);
    let commitment: Field = SFT::at(sft_contract_address).initialize_transfer_commitment(utils::token_id_1, owner, recipient, owner).call(&mut env.private());
    env.advance_block_by(1);

    assert(utils::get_commitment_stored(sft_contract_address, commitment), "Commitment not stored");

    let transfer_call_interface = SFT::at(sft_contract_address).transfer_private_to_commitment(owner, utils::token_id_1, commitment, 1);
    authwit_cheatcodes::add_private_authwit_from_call_interface(owner, recipient, transfer_call_interface);

    env.impersonate(recipient);
    transfer_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 1);
    assert(utils::get_commitment_stored(sft_contract_address, commitment), "Commitment not stored after transfer");
}

/// Test commitment works across different token types
#[test]
unconstrained fn sft_transfer_private_to_commitment_different_token_types_success() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);

    env.impersonate(minter);
    SFT::at(sft_contract_address).create_token_type(utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).create_token_type(utils::token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_2).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 2);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_2, 1);

    env.impersonate(owner);
    let commitment: Field = SFT::at(sft_contract_address).initialize_transfer_commitment(utils::token_id_1, owner, recipient, owner).call(&mut env.private());
    env.advance_block_by(1);

    SFT::at(sft_contract_address).transfer_private_to_commitment(owner, utils::token_id_1, commitment, 0).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_2, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_2, 0);
}

/// Test transfer fails for non-existent token
#[test(should_fail_with = "sft not found in private")]
unconstrained fn sft_transfer_private_to_commitment_non_existent_fail() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);

    env.impersonate(recipient);
    let commitment: Field = SFT::at(sft_contract_address).initialize_transfer_commitment(utils::token_id_1, owner, recipient, recipient).call(&mut env.private());
    env.advance_block_by(1);

    env.impersonate(owner);
    SFT::at(sft_contract_address).transfer_private_to_commitment(owner, utils::token_id_1, commitment, 0).call(&mut env.private());
}

/// Test transfer fails without authorization
#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn sft_transfer_private_to_commitment_unauthorized_fail() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_private(true);

    env.impersonate(recipient);
    let commitment: Field = SFT::at(sft_contract_address).initialize_transfer_commitment(utils::token_id_1, owner, recipient, recipient).call(&mut env.private());
    env.advance_block_by(1);

    let transfer_call_interface = SFT::at(sft_contract_address).transfer_private_to_commitment(owner, utils::token_id_1, commitment, 1);

    env.impersonate(recipient);
    transfer_call_interface.call(&mut env.private());
}

/// Test transfer fails with wrong authorization
#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn sft_transfer_private_to_commitment_wrong_authwit_fail() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_private(true);

    env.impersonate(recipient);
    let commitment: Field = SFT::at(sft_contract_address).initialize_transfer_commitment(utils::token_id_1, owner, recipient, recipient).call(&mut env.private());
    env.advance_block_by(1);

    let transfer_call_interface = SFT::at(sft_contract_address).transfer_private_to_commitment(owner, utils::token_id_1, commitment, 1);
    authwit_cheatcodes::add_private_authwit_from_call_interface(owner, owner, transfer_call_interface);

    env.impersonate(recipient);
    transfer_call_interface.call(&mut env.private());
}

/// Test transfer fails when SFT is in public state
#[test(should_fail_with = "sft not found in private")]
unconstrained fn sft_transfer_private_to_commitment_public_sft_fail() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_public(false);

    env.impersonate(recipient);
    let commitment: Field = SFT::at(sft_contract_address).initialize_transfer_commitment(utils::token_id_1, owner, recipient, recipient).call(&mut env.private());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 2);

    env.impersonate(owner);
    SFT::at(sft_contract_address).transfer_private_to_commitment(owner, utils::token_id_1, commitment, 0).call(&mut env.private());
}
