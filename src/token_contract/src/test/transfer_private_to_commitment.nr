use crate::test::utils::{self, mint_amount};
use crate::Token;
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test]
unconstrained fn transfer_private_to_commitment() {
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, 0 as u128);

    // Prepare commitment
    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(owner, recipient, owner),
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
    env.mine_block();

    // Check balances
    utils::check_private_balance(token_contract_address, owner, 0 as u128);
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn transfer_private_to_commitment_on_behalf_of_other() {
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(true);

    utils::check_private_balance(token_contract_address, owner, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, 0 as u128);

    let transfer_amount = mint_amount;

    // Prepare commitment
    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(owner, recipient, owner),
    );
    env.mine_block();

    let transfer_to_commitment_call_interface = Token::at(token_contract_address)
        .transfer_private_to_commitment(owner, commitment, transfer_amount, 0);

    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_to_commitment_call_interface,
    );

    // Transfer tokens
    env.call_private(recipient, transfer_to_commitment_call_interface);
    env.mine_block();

    // Check balances
    utils::check_private_balance(token_contract_address, owner, 0 as u128);
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
}
