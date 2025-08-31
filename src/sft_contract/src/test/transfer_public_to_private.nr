use crate::SFT;
use crate::test::utils;
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test]
unconstrained fn sft_transfer_public_to_private_success() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_public(false);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 2);

    env.impersonate(owner);
    SFT::at(sft_contract_address)
        .transfer_public_to_private(owner, recipient, utils::token_id_1, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 1);
}

#[test]
unconstrained fn sft_transfer_public_to_private_authorized_success() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_public(true);
    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 2);

    let transfer_call_interface = SFT::at(sft_contract_address).transfer_public_to_private(
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

    utils::check_public_balance(env, sft_contract_address, owner, utils::token_id_1, 1);
    utils::check_private_balance(sft_contract_address, recipient, utils::token_id_1, 1);
}

#[test(should_fail_with = "insufficient public balance")]
unconstrained fn sft_transfer_public_to_private_not_owned_fail() {
    let (env, sft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    utils::create_test_token_type(env, sft_contract_address, minter);

    env.impersonate(owner);
    SFT::at(sft_contract_address)
        .transfer_public_to_private(owner, recipient, utils::token_id_1, 0)
        .call(&mut env.private());
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn sft_transfer_public_to_private_unauthorized_fail() {
    let (env, sft_contract_address, owner, _, recipient) = utils::setup_and_mint_to_public(true);

    let transfer_call_interface = SFT::at(sft_contract_address).transfer_public_to_private(
        owner,
        recipient,
        utils::token_id_1,
        1,
    );

    env.impersonate(recipient);
    transfer_call_interface.call(&mut env.private());
}
