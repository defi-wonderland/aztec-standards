use crate::NFT;
use crate::test::utils;
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test]
unconstrained fn nft_transfer_private_to_public_with_commitment_success() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);

    // Transfer NFT with commitment
    let returned_commitment = env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            token_id,
            0,
        ),
    );

    // Verify ownership transfer
    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id);

    // Verify commitment is stored
    utils::check_commitment_is_stored(env, nft_contract_address, returned_commitment);
}

#[test]
unconstrained fn nft_transfer_private_to_public_with_commitment_authorized_success() {
    // Setup with account contracts and mint NFT to owner
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(true, token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);

    // Create transfer call interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, token_id, 1);

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        env,
        owner,
        recipient,
        transfer_call_interface,
    );

    // Impersonate recipient to perform the authorized transfer
    let returned_commitment = env.call_private(recipient, transfer_call_interface);

    // Verify ownership transfer
    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id);

    // Verify commitment is stored
    utils::check_commitment_is_stored(env, nft_contract_address, returned_commitment);
}

#[test]
unconstrained fn nft_transfer_private_to_public_with_commitment_and_finalize_success() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);

    // Transfer NFT with commitment
    let commitment = env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            token_id,
            0,
        ),
    );

    // Verify intermediate state (public ownership and commitment)
    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id);
    utils::check_commitment_is_stored(env, nft_contract_address, commitment);
}

#[test(should_fail_with = "nft not found in private to public")]
unconstrained fn nft_transfer_private_to_public_with_commitment_non_existent_fail() {
    // Setup but don't mint any NFT
    let (env, nft_contract_address, owner, _, recipient) = utils::setup_with_minter(false);
    let non_existent_token_id = 12345;

    // Attempt to transfer non-existent NFT
    let _ = env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            non_existent_token_id,
            0,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn nft_transfer_private_to_public_with_commitment_unauthorized_fail() {
    // Setup with account contracts
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(true, token_id);

    // Create transfer interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, token_id, 1);

    // Impersonate recipient but DON'T add authorization witness
    let _ = env.call_private(recipient, transfer_call_interface);
}

#[test(should_fail_with = "invalid commitment")]
unconstrained fn nft_transfer_private_to_public_with_commitment_and_finalize_invalid_commitment_fail() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Transfer NFT with commitment (ignore the returned commitment)
    let _ = env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            token_id,
            0,
        ),
    );

    // Create invalid commitment
    let invalid_commitment = 0xdeadbeef;

    // Attempt to finalize with invalid commitment
    env.call_public(
        recipient,
        NFT::at(nft_contract_address).transfer_public_to_commitment(
            recipient,
            token_id,
            invalid_commitment,
            0,
        ),
    );
}

#[test(should_fail_with = "invalid commitment")]
unconstrained fn nft_transfer_private_to_public_with_commitment_and_finalize_zero_commitment_fail() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Transfer NFT with commitment (ignore the returned commitment)
    let _ = env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            token_id,
            0,
        ),
    );

    // Create zero commitment
    let zero_commitment = 0;

    // Attempt to finalize with zero commitment
    env.call_public(
        recipient,
        NFT::at(nft_contract_address).transfer_public_to_commitment(
            recipient,
            token_id,
            zero_commitment,
            0,
        ),
    );
}
