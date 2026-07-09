use crate::MultiToken;
use crate::test::utils::{self, mint_amount};
use aztec::protocol::traits::ToField;
use multitoken_authorization_contract::MultiTokenAuthorizationContract;

#[test]
unconstrained fn auth_hook_called_on_transfer_public_to_public() {
    // public-context fn -> authorize_public -> from_public = true
    let (env, multitoken_contract_address, owner, recipient, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    let id: Field = 1;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, mint_amount),
    );

    let transfer_amount = mint_amount / (2 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_public_to_public(
        owner,
        recipient,
        id,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    env.call_public(owner, call_interface);

    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        id,
        transfer_amount,
        expected_selector,
        true,
    );
}

#[test]
unconstrained fn auth_hook_called_on_burn_public() {
    // public-context fn -> authorize_public -> from_public = true
    let (env, multitoken_contract_address, owner, _, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    let id: Field = 1;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, mint_amount),
    );

    let burn_amount = mint_amount / (2 as u128);
    let call_interface =
        MultiToken::at(multitoken_contract_address).burn_public(owner, id, burn_amount, 0);
    let expected_selector = call_interface.selector.to_field();

    env.call_public(owner, call_interface);

    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        id,
        burn_amount,
        expected_selector,
        true,
    );
}

#[test]
unconstrained fn auth_hook_called_on_transfer_public_to_commitment() {
    // public-context fn -> authorize_public -> from_public = true
    let (env, multitoken_contract_address, owner, recipient, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    let id: Field = 1;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, mint_amount),
    );

    // Initialize the commitment target (does not fire the hook).
    let commitment = env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    let transfer_amount = mint_amount / (2 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_public_to_commitment(
        owner,
        id,
        commitment,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    env.call_public(owner, call_interface);

    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        id,
        transfer_amount,
        expected_selector,
        true,
    );
}

#[test]
unconstrained fn auth_hook_called_on_transfer_private_to_private() {
    // private-context fn -> authorize_private -> from_public = false
    let (env, multitoken_contract_address, owner, recipient, _, auth_contract) =
        utils::setup_and_mint_to_private_with_auth(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (2 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_private_to_private(
        owner,
        recipient,
        id,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    env.call_private(owner, call_interface);

    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        id,
        transfer_amount,
        expected_selector,
        false,
    );
}

#[test]
unconstrained fn auth_hook_called_on_transfer_private_to_public() {
    // private-context fn -> authorize_private -> from_public = false
    let (env, multitoken_contract_address, owner, recipient, _, auth_contract) =
        utils::setup_and_mint_to_private_with_auth(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (2 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_private_to_public(
        owner,
        recipient,
        id,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    env.call_private(owner, call_interface);

    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        id,
        transfer_amount,
        expected_selector,
        false,
    );
}

#[test]
unconstrained fn auth_hook_called_on_transfer_public_to_private() {
    // ARC-403 caveat: transfer_public_to_private is a PRIVATE fn despite operating on the public balance, so it
    // dispatches to authorize_private -> from_public = false.
    let (env, multitoken_contract_address, owner, recipient, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    let id: Field = 1;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, mint_amount),
    );

    let transfer_amount = mint_amount / (2 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_public_to_private(
        owner,
        recipient,
        id,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    env.call_private(owner, call_interface);

    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        id,
        transfer_amount,
        expected_selector,
        false,
    );
}

#[test]
unconstrained fn auth_hook_called_on_transfer_private_to_commitment() {
    // private-context fn -> authorize_private -> from_public = false
    let (env, multitoken_contract_address, owner, recipient, _, auth_contract) =
        utils::setup_and_mint_to_private_with_auth(false, 1);

    // Initialize the commitment target (does not fire the hook).
    let commitment = env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    let id: Field = 1;
    let transfer_amount = mint_amount / (2 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_private_to_commitment(
        owner,
        id,
        commitment,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    env.call_private(owner, call_interface);

    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        id,
        transfer_amount,
        expected_selector,
        false,
    );
}

#[test]
unconstrained fn auth_hook_called_on_burn_private() {
    // private-context fn -> authorize_private -> from_public = false
    let (env, multitoken_contract_address, owner, _, _, auth_contract) =
        utils::setup_and_mint_to_private_with_auth(false, 1);

    let id: Field = 1;
    let burn_amount = mint_amount / (2 as u128);
    let call_interface =
        MultiToken::at(multitoken_contract_address).burn_private(owner, id, burn_amount, 0);
    let expected_selector = call_interface.selector.to_field();

    env.call_private(owner, call_interface);

    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        id,
        burn_amount,
        expected_selector,
        false,
    );
}

#[test]
unconstrained fn auth_hook_records_correct_id() {
    // Focused id-integrity: move a distinctive id (42, distinct from the from address and amount) and assert the
    // hook recorded exactly that id (guards against the id arg being dropped or confused with amount/from).
    let (env, multitoken_contract_address, owner, recipient, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    let id: Field = 42;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, mint_amount),
    );

    let transfer_amount: u128 = 1_234;
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_public_to_public(
        owner,
        recipient,
        id,
        transfer_amount,
        0,
    );
    let expected_selector = call_interface.selector.to_field();

    env.call_public(owner, call_interface);

    // assert_auth_call asserts the recorded id == 42 alongside from/amount/selector/from_public.
    utils::assert_auth_call(
        env,
        auth_contract,
        owner,
        id,
        transfer_amount,
        expected_selector,
        true,
    );
}

// ARC-403 hook is NOT fired on mints: mints are minter-gated and never call the hook.

#[test]
unconstrained fn auth_hook_not_called_on_mint_to_public() {
    let (env, multitoken_contract_address, owner, _, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    let id: Field = 1;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, mint_amount),
    );

    utils::assert_auth_not_called(env, auth_contract);
}

#[test]
unconstrained fn auth_hook_not_called_on_mint_to_private() {
    let (env, multitoken_contract_address, owner, _, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    let id: Field = 1;
    utils::mint_to_private(
        env,
        multitoken_contract_address,
        owner,
        id,
        mint_amount,
        minter,
    );

    utils::assert_auth_not_called(env, auth_contract);
}

#[test]
unconstrained fn auth_hook_not_called_on_mint_to_commitment() {
    let (env, multitoken_contract_address, _, recipient, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    // Initialize the commitment target (does not fire the hook).
    let commitment = env.call_private(
        minter,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(
            recipient,
            minter,
        ),
    );

    let id: Field = 1;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_commitment(id, commitment, mint_amount),
    );

    utils::assert_auth_not_called(env, auth_contract);
}

// ARC-403 hook rejection: the hook runs BEFORE balance mutation; set_should_revert -> "operation not authorized".

#[test(should_fail_with = "operation not authorized")]
unconstrained fn transfer_public_to_public_reverts_when_auth_rejects() {
    let (env, multitoken_contract_address, owner, recipient, minter, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    let id: Field = 1;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, mint_amount),
    );

    // Enable reject mode on the spy.
    env.call_public(
        owner,
        MultiTokenAuthorizationContract::at(auth_contract).set_should_revert(true),
    );

    let transfer_amount = mint_amount / (2 as u128);
    env.call_public(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_public_to_public(
            owner,
            recipient,
            id,
            transfer_amount,
            0,
        ),
    );
}

#[test(should_fail_with = "operation not authorized")]
unconstrained fn transfer_private_to_private_reverts_when_auth_rejects() {
    // The private hook enqueues record_call_internal to public, where the assert fires and propagates.
    let (env, multitoken_contract_address, owner, recipient, _, auth_contract) =
        utils::setup_and_mint_to_private_with_auth(false, 1);

    // Enable reject mode on the spy.
    env.call_public(
        owner,
        MultiTokenAuthorizationContract::at(auth_contract).set_should_revert(true),
    );

    let id: Field = 1;
    let transfer_amount = mint_amount / (2 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_private(
            owner,
            recipient,
            id,
            transfer_amount,
            0,
        ),
    );
}
