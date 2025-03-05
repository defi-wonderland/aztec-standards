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

    // Transfer tokens to recipient
    utils::transfer_private_to_private(
        env,
        token_contract_address,
        sender,
        recipient,
        transfer_amount,
    );

    // Check balances
    let mut new_balance = TRANSFER_CAP.add(U128::one()).sub(transfer_amount);
    utils::check_private_balance(token_contract_address, sender, new_balance);
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);

    // Transfer more tokens to recipient to reach cap
    utils::transfer_private_to_private(
        env,
        token_contract_address,
        sender,
        recipient,
        transfer_amount,
    );

    // Check balances
    new_balance -= transfer_amount;
    utils::check_private_balance(token_contract_address, sender, new_balance);
    utils::check_private_balance(
        token_contract_address,
        recipient,
        transfer_amount.mul(U128::from_integer(2)),
    );
}

#[test(should_fail_with = "Transfer amount exceeds private transfer cap")]
unconstrained fn private_transfer_more_than_cap_one_transfer() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, sender, recipient) = utils::setup(TRANSFER_CAP);

    env.advance_block_by(5);

    let mint_amount = TRANSFER_CAP.add(U128::one());

    // Mint tokens to sender
    utils::mint_to_private(env, token_contract_address, sender, mint_amount);

    // Transfer tokens to recipient
    utils::transfer_private_to_private(env, token_contract_address, sender, recipient, mint_amount);
}

#[test(should_fail_with = "Transfer amount exceeds private transfer cap")]
unconstrained fn private_transfer_more_than_cap_multiple_transfer() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, sender, recipient) = utils::setup(TRANSFER_CAP);

    env.advance_block_by(5);

    let transfer_amount = TRANSFER_CAP;
    let mint_amount = transfer_amount.add(U128::one());

    // Mint tokens to sender
    utils::mint_to_private(env, token_contract_address, sender, mint_amount);

    // Transfer tokens to recipient
    utils::transfer_private_to_private(
        env,
        token_contract_address,
        sender,
        recipient,
        transfer_amount,
    );

    // Check balances
    let mut new_balance = mint_amount.sub(transfer_amount);
    utils::check_private_balance(token_contract_address, sender, new_balance);
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);

    // Private transfer one token should revert because we are over the cap
    utils::transfer_private_to_private(env, token_contract_address, sender, recipient, U128::one());
}

#[test]
unconstrained fn private_transfer_reset_accumulator() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (env, token_contract_address, owner, sender, recipient) = utils::setup(TRANSFER_CAP);

    env.advance_block_by(5);

    let transfer_amount = TRANSFER_CAP;
    let mint_amount = transfer_amount.add(transfer_amount);

    // Mint tokens to sender
    utils::mint_to_private(env, token_contract_address, sender, mint_amount);

    // Transfer tokens to recipient
    utils::transfer_private_to_private(
        env,
        token_contract_address,
        sender,
        recipient,
        transfer_amount,
    );

    // Check balances
    let mut new_balance = mint_amount.sub(transfer_amount);
    utils::check_private_balance(token_contract_address, sender, new_balance);
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);

    // Reset accumulator
    // Impersonate sender to perform the call
    env.impersonate(sender);
    // Transfer tokens
    PrivateTransferCapToken::at(token_contract_address).reset_transfer_accumulator(sender, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Private transfer should not revert because we have reset the accumulator
    utils::transfer_private_to_private(
        env,
        token_contract_address,
        sender,
        recipient,
        transfer_amount,
    );
}

