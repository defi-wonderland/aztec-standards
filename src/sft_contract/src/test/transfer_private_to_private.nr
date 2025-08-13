use crate::SFT;
use crate::test::utils;
use aztec::test::helpers::authwit as authwit_cheatcodes;

/// Test successful private to private transfer
#[test]
unconstrained fn sft_transfer_private_to_private_success() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_private(false);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 2);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 0);

    env.impersonate(owner);
    SFT::at(sft_contract_address)
        .transfer_private_to_private(owner, recipient, utils::token_id_1, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 1);
}

/// Test successful self transfer
#[test]
unconstrained fn sft_transfer_private_to_private_self_success() {
    let (env, sft_contract_address, owner, _, _) = utils::setup_and_mint_to_private(false);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 2);

    env.impersonate(owner);
    SFT::at(sft_contract_address)
        .transfer_private_to_private(owner, owner, utils::token_id_1, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 2);
}

/// Test successful authorized transfer
#[test]
unconstrained fn sft_transfer_private_to_private_authorized_success() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_private(true);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 2);

    let transfer_call_interface = SFT::at(sft_contract_address).transfer_private_to_private(
        owner,
        recipient,
        utils::token_id_1,
        1,
    );
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_call_interface,
    );

    env.impersonate(recipient);
    transfer_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 1);
}

/// Test transfer across different token types
#[test]
unconstrained fn sft_transfer_private_to_private_different_token_types_success() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);

    env.impersonate(minter);
    SFT::at(sft_contract_address).create_token_type(utils::token_id_1).call(&mut env.public());
    SFT::at(sft_contract_address).create_token_type(utils::token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    env.impersonate(minter);
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_1).call(&mut env.private());
    SFT::at(sft_contract_address).mint_to_private(owner, utils::token_id_2).call(&mut env.private());
    env.advance_block_by(1);

    env.impersonate(owner);
    SFT::at(sft_contract_address)
        .transfer_private_to_private(owner, recipient, utils::token_id_1, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    utils::check_private_balance(sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, owner, utils::token_id_2, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_2, 0);
}

/// Test transfer fails for non-existent token
#[test(should_fail_with = "sft not found in private")]
unconstrained fn sft_transfer_private_to_private_non_existent_fail() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);

    env.impersonate(owner);
    SFT::at(sft_contract_address)
        .transfer_private_to_private(owner, recipient, utils::token_id_1, 0)
        .call(&mut env.private());
}

/// Test transfer fails without authorization
#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn sft_transfer_private_to_private_unauthorized_fail() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_private(true);
    let transfer_call_interface = SFT::at(sft_contract_address).transfer_private_to_private(
        owner,
        recipient,
        utils::token_id_1,
        1,
    );

    env.impersonate(recipient);
    transfer_call_interface.call(&mut env.private());
}

/// Test transfer fails with wrong authorization
#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn sft_transfer_private_to_private_wrong_authwit_fail() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_private(true);

    let transfer_call_interface = SFT::at(sft_contract_address).transfer_private_to_private(
        owner,
        recipient,
        utils::token_id_1,
        1,
    );
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        owner,
        transfer_call_interface,
    );

    env.impersonate(recipient);
    transfer_call_interface.call(&mut env.private());
}

/// Test transfer fails when SFT is in public state
#[test(should_fail_with = "sft not found in private")]
unconstrained fn sft_transfer_private_to_private_public_sft_fail() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_public(false);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 2);

    env.impersonate(owner);
    SFT::at(sft_contract_address)
        .transfer_private_to_private(owner, recipient, utils::token_id_1, 0)
        .call(&mut env.private());
}
