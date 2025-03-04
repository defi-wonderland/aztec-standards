use crate::FeeOnTransferToken;
use crate::test::utils;

global FEE_PERCENTAGE: U128 = U128::from_integer(5);

#[test]
unconstrained fn fee_on_transfer_private() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, sender, recipient) = utils::setup();

    let transfer_amount = U128::from_integer(1000);

    // Set fee to FEE_PERCENTAGE
    env.impersonate(owner);
    FeeOnTransferToken::at(token_contract_address).set_fee_on_transfer(FEE_PERCENTAGE).call(
        &mut env.public(),
    );
    env.advance_block_by(5);

    // Mint tokens to sender
    utils::mint_to_private(env, token_contract_address, sender, transfer_amount);

    // Impersonate sender to perform the call
    env.impersonate(sender);
    // Transfer tokens
    FeeOnTransferToken::at(token_contract_address)
        .transfer_private_to_private(sender, recipient, transfer_amount, 0)
        .call(&mut env.private());

    // Check balances
    let fee_amount = transfer_amount * FEE_PERCENTAGE / U128::from_integer(100);
    utils::check_private_balance(token_contract_address, sender, U128::zero());
    utils::check_private_balance(token_contract_address, owner, fee_amount);
    utils::check_private_balance(
        token_contract_address,
        recipient,
        transfer_amount - fee_amount,
    );
}

#[test]
unconstrained fn fee_on_transfer_public() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, sender, recipient) = utils::setup();

    let transfer_amount = U128::from_integer(1000);

    // Set fee to FEE_PERCENTAGE
    env.impersonate(owner);
    FeeOnTransferToken::at(token_contract_address).set_fee_on_transfer(FEE_PERCENTAGE).call(
        &mut env.public(),
    );
    env.advance_block_by(5);

    // Mint tokens to sender
    utils::mint_to_public(env, token_contract_address, sender, transfer_amount);

    // Impersonate sender to perform the call
    env.impersonate(sender);
    // Transfer tokens
    FeeOnTransferToken::at(token_contract_address)
        .transfer_public_to_public(sender, recipient, transfer_amount, 0)
        .call(&mut env.public());

    // Check balances
    let fee_amount = transfer_amount * FEE_PERCENTAGE / U128::from_integer(100);
    utils::check_public_balance(token_contract_address, sender, U128::zero());
    utils::check_public_balance(token_contract_address, owner, fee_amount);
    utils::check_public_balance(
        token_contract_address,
        recipient,
        transfer_amount - fee_amount,
    );
}
