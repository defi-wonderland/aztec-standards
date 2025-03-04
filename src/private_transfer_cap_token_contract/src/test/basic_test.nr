use crate::PrivateTransferCapToken;
use crate::test::utils;

global TRANSFER_CAP: U128 = U128::from_integer(200);

#[test]
unconstrained fn private_transfer_less_than_cap() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, sender, recipient) = utils::setup(TRANSFER_CAP);

    env.advance_block_by(5);

    let transfer_amount = U128::from_integer(100);

    // Mint tokens to sender
    utils::mint_to_private(
        env,
        token_contract_address,
        sender,
        TRANSFER_CAP.add(U128::one()),
    );

    // Impersonate sender to perform the call
    env.impersonate(sender);
    // Transfer tokens
    PrivateTransferCapToken::at(token_contract_address)
        .transfer_private_to_private(sender, recipient, transfer_amount, 0)
        .call(&mut env.private());

    // Check balances
    let mut new_balance = TRANSFER_CAP.add(U128::one()).sub(transfer_amount);
    utils::check_private_balance(token_contract_address, sender, new_balance);
    utils::check_private_balance(
        token_contract_address,
        recipient,
        transfer_amount,
    );

    // Impersonate sender to perform the call
    env.impersonate(sender);
    // Transfer a second time
    PrivateTransferCapToken::at(token_contract_address)
        .transfer_private_to_private(sender, recipient, transfer_amount, 0)
        .call(&mut env.private());

    // Check balances
    new_balance -= transfer_amount;
    utils::check_private_balance(token_contract_address, sender, new_balance);
    utils::check_private_balance(
        token_contract_address,
        recipient,
        transfer_amount.mul(U128::from_integer(2)),
    );
}

#[test(should_fail)]
unconstrained fn private_transfer_more_than_cap_one_transfer() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, sender, recipient) = utils::setup(TRANSFER_CAP);

    env.advance_block_by(5);

    let mint_amount = TRANSFER_CAP.add(U128::one());

    // Mint tokens to sender
    utils::mint_to_private(
        env,
        token_contract_address,
        sender,
        mint_amount,
    );

    // Impersonate sender to perform the call
    env.impersonate(sender);
    // Private transfer should revert because we are going over the cap
    PrivateTransferCapToken::at(token_contract_address)
        .transfer_private_to_private(sender, recipient, mint_amount, 0)
        .call(&mut env.private());
}

#[test(should_fail)]
unconstrained fn private_transfer_more_than_cap_multiple_transfer() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, sender, recipient) = utils::setup(TRANSFER_CAP);

    env.advance_block_by(5);

    let transfer_amount = TRANSFER_CAP;
    let mint_amount = transfer_amount.add(U128::one());

    // Mint tokens to sender
    utils::mint_to_private(
        env,
        token_contract_address,
        sender,
        mint_amount,
    );

    // Impersonate sender to perform the call
    env.impersonate(sender);
    // Transfer tokens
    PrivateTransferCapToken::at(token_contract_address)
        .transfer_private_to_private(sender, recipient, transfer_amount, 0)
        .call(&mut env.private());

    // Check balances
    let mut new_balance = mint_amount.sub(transfer_amount);
    utils::check_private_balance(token_contract_address, sender, new_balance);
    utils::check_private_balance(
        token_contract_address,
        recipient,
        transfer_amount,
    );

    // Private transfer should revert because we are over the cap
    env.impersonate(sender);
    PrivateTransferCapToken::at(token_contract_address)
        .transfer_private_to_private(sender, recipient, U128::one(), 0)
        .call(&mut env.private());
}

