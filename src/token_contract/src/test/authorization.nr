use crate::test::utils::{self, mint_amount};
use crate::Token;
use authorization_contract::AuthorizationContract;
use aztec::protocol::traits::ToField;

#[test]
unconstrained fn authorization_hook_called_on_transfer_public_to_public() {
    // Setup with auth contract; hook fires on every transfer
    let (mut env, token_contract_address, owner, recipient, auth_contract) =
        utils::setup_with_auth_contract(false, mint_amount);

    // Capture selector from the call interface before executing
    let transfer_amount = mint_amount / 2;
    let call_interface = Token::at(token_contract_address).transfer_public_to_public(
        owner,
        recipient,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    // Transfer tokens
    env.call_public(owner, call_interface);

    // Hook recorded (from, amount, selector) from the transfer
    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        transfer_amount,
        expected_selector,
    );
}

#[test]
unconstrained fn authorization_hook_called_on_burn_public() {
    // Setup with auth contract; hook fires on every burn
    let (mut env, token_contract_address, owner, _, auth_contract) =
        utils::setup_with_auth_contract(false, mint_amount);

    // Capture selector from the call interface before executing
    let burn_amount = mint_amount / 2;
    let call_interface = Token::at(token_contract_address).burn_public(owner, burn_amount, 0);
    let expected_selector = call_interface.selector.to_field();

    // Burn tokens
    env.call_public(owner, call_interface);

    // Hook recorded (from, amount, selector) from the burn
    utils::assert_auth_call(env, auth_contract, owner, burn_amount, expected_selector);
}

#[test]
unconstrained fn authorization_hook_called_on_transfer_public_to_commitment() {
    // Setup with auth contract; hook fires on every transfer
    let (mut env, token_contract_address, owner, recipient, auth_contract) =
        utils::setup_with_auth_contract(false, mint_amount);

    // Initialize a transfer commitment so we have a valid target; this does not fire the hook
    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    // Capture selector from the call interface before executing
    let transfer_amount = mint_amount / 2;
    let call_interface = Token::at(token_contract_address).transfer_public_to_commitment(
        owner,
        commitment,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    // Transfer tokens into the commitment
    env.call_public(owner, call_interface);

    // Hook recorded (from, amount, selector) from the transfer
    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        transfer_amount,
        expected_selector,
    );
}

#[test]
unconstrained fn authorization_hook_called_on_burn_private() {
    // Setup with auth contract and private balance; mint does not fire the hook
    let (env, token_contract_address, owner, _, _, auth_contract) =
        utils::setup_and_mint_to_private_with_auth(false);

    // Capture selector from the call interface before executing
    let burn_amount = mint_amount / 2;
    let call_interface = Token::at(token_contract_address).burn_private(owner, burn_amount, 0);
    let expected_selector = call_interface.selector.to_field();

    // Burn tokens
    env.call_private(owner, call_interface);

    // Hook recorded (from, amount, selector) from the burn
    utils::assert_auth_call(env, auth_contract, owner, burn_amount, expected_selector);
}

#[test]
unconstrained fn authorization_hook_called_on_transfer_private_to_private() {
    // Setup with auth contract and private balance; mint does not fire the hook
    let (mut env, token_contract_address, owner, recipient, _, auth_contract) =
        utils::setup_and_mint_to_private_with_auth(false);

    // Capture selector from the call interface before executing
    let transfer_amount = mint_amount / 2;
    let call_interface = Token::at(token_contract_address).transfer_private_to_private(
        owner,
        recipient,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    // Transfer tokens
    env.call_private(owner, call_interface);

    // Hook recorded (from, amount, selector) from the transfer
    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        transfer_amount,
        expected_selector,
    );
}

#[test]
unconstrained fn authorization_hook_called_on_transfer_private_to_public() {
    // Setup with auth contract and private balance; mint does not fire the hook
    let (mut env, token_contract_address, owner, recipient, _, auth_contract) =
        utils::setup_and_mint_to_private_with_auth(false);

    // Capture selector from the call interface before executing
    let transfer_amount = mint_amount / 2;
    let call_interface = Token::at(token_contract_address).transfer_private_to_public(
        owner,
        recipient,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    // Transfer tokens
    env.call_private(owner, call_interface);

    // Hook recorded (from, amount, selector) from the transfer
    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        transfer_amount,
        expected_selector,
    );
}

#[test]
unconstrained fn authorization_hook_called_on_transfer_public_to_private() {
    // Setup with auth contract; hook fires even though the source balance is public
    let (mut env, token_contract_address, owner, recipient, auth_contract) =
        utils::setup_with_auth_contract(false, mint_amount);

    // Capture selector from the call interface before executing
    let transfer_amount = mint_amount / 2;
    let call_interface = Token::at(token_contract_address).transfer_public_to_private(
        owner,
        recipient,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    // Function is private despite operating on public balance (ARC-403 privacy caveat)
    env.call_private(owner, call_interface);

    // Hook recorded (from, amount, selector) from the transfer
    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        transfer_amount,
        expected_selector,
    );
}

#[test]
unconstrained fn authorization_hook_called_on_transfer_private_to_commitment() {
    // Setup with auth contract and private balance; mint does not fire the hook
    let (mut env, token_contract_address, owner, recipient, _, auth_contract) =
        utils::setup_and_mint_to_private_with_auth(false);

    // Initialize a transfer commitment so we have a valid target; this does not fire the hook
    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    // Capture selector from the call interface before executing
    let transfer_amount = mint_amount / 2;
    let call_interface = Token::at(token_contract_address).transfer_private_to_commitment(
        owner,
        commitment,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    // Transfer tokens into the commitment
    env.call_private(owner, call_interface);

    // Hook recorded (from, amount, selector) from the transfer
    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        transfer_amount,
        expected_selector,
    );
}

#[test]
unconstrained fn authorization_hook_called_on_transfer_private_to_public_with_commitment() {
    // Setup with auth contract and private balance; mint does not fire the hook
    let (mut env, token_contract_address, owner, recipient, _, auth_contract) =
        utils::setup_and_mint_to_private_with_auth(false);

    // Capture selector from the call interface before executing
    // Note: commitment is initialized internally by this function, no explicit init needed
    let transfer_amount = mint_amount / 2;
    let call_interface = Token::at(token_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, transfer_amount, 0);
    let expected_selector = call_interface.selector.to_field();

    // Transfer tokens
    let _ = env.call_private(owner, call_interface);

    // Hook recorded (from, amount, selector) from the transfer
    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        transfer_amount,
        expected_selector,
    );
}

#[test]
unconstrained fn authorization_hook_not_called_on_mint_to_public() {
    // Setup with auth contract and minter; no prior mint so last_call is still default
    let (mut env, token_contract_address, owner, _, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    // Mint to public balance
    env.call_public(minter, Token::at(token_contract_address).mint_to_public(owner, mint_amount));

    // Hook must not be invoked on mint (ARC-403 design: mints are gated by minter role)
    utils::assert_auth_not_called(env, auth_contract);
}

#[test]
unconstrained fn authorization_hook_not_called_on_mint_to_private() {
    // Setup with auth contract and minter; no prior mint so last_call is still default
    let (env, token_contract_address, owner, _, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    // Mint to private balance (helper handles the getRandomField oracle mock)
    utils::mint_to_private(env, token_contract_address, owner, mint_amount, minter);

    // Hook must not be invoked on mint (ARC-403 design: mints are gated by minter role)
    utils::assert_auth_not_called(env, auth_contract);
}

#[test]
unconstrained fn authorization_hook_not_called_on_mint_to_commitment() {
    // Setup with auth contract and minter; no prior mint so last_call is still default
    let (mut env, token_contract_address, _, recipient, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    // Initialize a transfer commitment as the mint target; this does not fire the hook
    let commitment = env.call_private(
        minter,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, minter),
    );

    // Mint into the commitment
    env.call_public(
        minter,
        Token::at(token_contract_address).mint_to_commitment(commitment, mint_amount),
    );

    // Hook must not be invoked on mint (ARC-403 design: mints are gated by minter role)
    utils::assert_auth_not_called(env, auth_contract);
}

#[test(should_fail_with = "operation not authorized")]
unconstrained fn transfer_public_to_public_reverts_when_auth_rejects() {
    // Setup with auth contract; hook fires on every transfer
    let (mut env, token_contract_address, owner, recipient, auth_contract) =
        utils::setup_with_auth_contract(false, mint_amount);

    // Enable reject mode on the auth contract
    env.call_public(owner, AuthorizationContract::at(auth_contract).set_should_revert(true));

    // Transfer must revert because the hook rejects
    let transfer_amount = mint_amount / 2;
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_public(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );
}

#[test(should_fail_with = "operation not authorized")]
unconstrained fn transfer_private_to_private_reverts_when_auth_rejects() {
    // Setup with auth contract and private balance; mint does not fire the hook
    let (mut env, token_contract_address, owner, recipient, _, auth_contract) =
        utils::setup_and_mint_to_private_with_auth(false);

    // Enable reject mode on the auth contract
    env.call_public(owner, AuthorizationContract::at(auth_contract).set_should_revert(true));

    // Transfer must revert because the hook rejects; authorize_private enqueues
    // record_call_internal to public, where the assert fires and propagates
    let transfer_amount = mint_amount / 2;
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_private(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );
}

#[test]
unconstrained fn transfer_public_to_public_succeeds_when_auth_disabled() {
    // Default setup wires the token with `auth_contract = zero`, disabling the hook
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);

    // Transfer must succeed without ever invoking an authorization contract
    let transfer_amount = mint_amount / 2;
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_public(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    // Balances moved, confirming the short-circuit path did not block the transfer
    utils::check_public_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_public_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn transfer_private_to_private_succeeds_when_auth_disabled() {
    // Default setup wires the token with `auth_contract = zero`, disabling the hook
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_private_without_minter(false);

    // Transfer must succeed without ever invoking an authorization contract
    let transfer_amount = mint_amount / 2;
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_private(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    // Balances moved, confirming the short-circuit path did not block the transfer
    utils::check_private_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_private_balance(env, token_contract_address, recipient, transfer_amount);
}
