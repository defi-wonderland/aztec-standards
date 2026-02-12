use crate::test::utils::{self, mint_amount};
use crate::Token;
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

#[test]
unconstrained fn transfer_private_to_commitment() {
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(env, token_contract_address, owner, mint_amount);
    utils::check_private_balance(env, token_contract_address, recipient, 0 as u128);

    // Prepare commitment
    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    // Transfer tokens
    let transfer_amount = mint_amount;
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_commitment(
            owner,
            commitment,
            transfer_amount,
            0,
        ),
    );

    // Check balances
    utils::check_private_balance(env, token_contract_address, owner, 0 as u128);
    utils::check_private_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn transfer_private_to_commitment_on_behalf_of_other() {
    let (mut env, token_contract_address, owner, recipient, proxy) =
        utils::setup_and_mint_to_private_with_proxy();

    utils::check_private_balance(env, token_contract_address, owner, mint_amount);
    utils::check_private_balance(env, token_contract_address, recipient, 0 as u128);

    let transfer_amount = mint_amount;

    // Prepare commitment with proxy as the completer (since proxy will be msg_sender in the
    // token contract when calling via the proxy)
    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, proxy),
    );

    let transfer_to_commitment_call_interface = Token::at(token_contract_address)
        .transfer_private_to_commitment(owner, commitment, transfer_amount, 0);

    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        owner,
        proxy,
        transfer_to_commitment_call_interface,
    );

    // Transfer tokens via proxy
    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_4(
            transfer_to_commitment_call_interface.target_contract,
            transfer_to_commitment_call_interface.selector,
            transfer_to_commitment_call_interface.args,
        ),
    );

    // Check balances
    utils::check_private_balance(env, token_contract_address, owner, 0 as u128);
    utils::check_private_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test(should_fail_with = "Nullifier witness not found for nullifier")]
unconstrained fn transfer_private_to_commitment_wrong_completer() {
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(env, token_contract_address, owner, mint_amount);
    utils::check_private_balance(env, token_contract_address, recipient, 0 as u128);

    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, recipient),
    );

    // Transfer tokens
    let transfer_amount = mint_amount;
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_commitment(
            owner,
            commitment,
            transfer_amount,
            0,
        ),
    );

    // Check balances
    utils::check_private_balance(env, token_contract_address, owner, 0 as u128);
    utils::check_private_balance(env, token_contract_address, recipient, transfer_amount);
}
