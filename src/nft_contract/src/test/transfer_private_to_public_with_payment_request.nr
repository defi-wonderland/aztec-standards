use crate::NFT;
use crate::test::utils;
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test]
unconstrained fn nft_transfer_private_to_public_with_payment_request_success() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id);

    // Transfer NFT with payment request
    env.impersonate(owner);
    let returned_payment_request = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_payment_request(owner, recipient, token_id, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify ownership transfer
    utils::assert_private_nft_nullified(nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id);

    // Verify payment request is stored
    assert(
        utils::get_commitment_stored(nft_contract_address, returned_payment_request),
        "Payment request not stored",
    );
}

#[test]
unconstrained fn nft_transfer_private_to_public_with_payment_request_authorized_success() {
    // Setup with account contracts and mint NFT to owner
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(true, token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id);

    // Create transfer call interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_payment_request(owner, recipient, token_id, 1);

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_call_interface,
    );

    // Impersonate recipient to perform the authorized transfer
    env.impersonate(recipient);
    let returned_payment_request = transfer_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    // Verify ownership transfer
    utils::assert_private_nft_nullified(nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id);

    // Verify payment request is stored
    assert(
        utils::get_commitment_stored(nft_contract_address, returned_payment_request),
        "Payment request not stored",
    );
}

#[test]
unconstrained fn nft_transfer_private_to_public_with_payment_request_and_finalize_success() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id);

    // Transfer NFT with payment request
    env.impersonate(owner);
    let payment_request = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_payment_request(owner, recipient, token_id, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify intermediate state (public ownership and payment request)
    utils::assert_private_nft_nullified(nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id);
    assert(
        utils::get_commitment_stored(nft_contract_address, payment_request),
        "Payment request not stored",
    );
}

#[test(should_fail_with = "nft not found in private to public")]
unconstrained fn nft_transfer_private_to_public_with_payment_request_non_existent_fail() {
    // Setup but don't mint any NFT
    let (env, nft_contract_address, owner, _, recipient) = utils::setup_with_minter(false);
    let non_existent_token_id = 12345;

    // Attempt to transfer non-existent NFT
    env.impersonate(owner);
    let _ = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_payment_request(owner, recipient, non_existent_token_id, 0)
        .call(&mut env.private());
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn nft_transfer_private_to_public_with_payment_request_unauthorized_fail() {
    // Setup with account contracts
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(true, token_id);

    // Create transfer interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_payment_request(owner, recipient, token_id, 1);

    // Impersonate recipient but DON'T add authorization witness
    env.impersonate(recipient);
    let _ = transfer_call_interface.call(&mut env.private());
}

#[test(should_fail_with = "invalid payment request")]
unconstrained fn nft_transfer_private_to_public_with_payment_request_and_finalize_invalid_payment_request_fail() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Transfer NFT with payment request (ignore the returned payment request)
    env.impersonate(owner);
    let _ = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_payment_request(owner, recipient, token_id, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Create invalid payment request
    let invalid_payment_request = 0xdeadbeef;

    // Attempt to finalize with invalid payment request
    env.impersonate(recipient);
    let _ = NFT::at(nft_contract_address)
        .transfer_public_to_payment_request(recipient, token_id, invalid_payment_request, 0)
        .call(&mut env.public());
}

#[test(should_fail_with = "invalid payment request")]
unconstrained fn nft_transfer_private_to_public_with_payment_request_and_finalize_zero_payment_request_fail() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Transfer NFT with payment request (ignore the returned payment request)
    env.impersonate(owner);
    let _ = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_payment_request(owner, recipient, token_id, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Create zero payment request
    let zero_payment_request = 0;

    // Attempt to finalize with zero payment request
    env.impersonate(recipient);
    NFT::at(nft_contract_address)
        .transfer_public_to_payment_request(recipient, token_id, zero_payment_request, 0)
        .call(&mut env.public());
}
