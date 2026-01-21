use crate::NFT;
use crate::test::utils;
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test]
unconstrained fn nft_transfer_private_to_commitment_success() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);

    // Prepare commitment
    let commitment = env.call_private(
        owner,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    // Verify commitment is stored
    utils::check_commitment_is_stored(env, nft_contract_address, commitment);

    // Transfer NFT to commitment
    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_commitment(owner, token_id, commitment, 0),
    );

    // Verify NFT is removed from owner and in commitment
    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
    // NFT should be in recipient's private set
    utils::assert_owns_private_nft(env, nft_contract_address, recipient, token_id);
    utils::check_commitment_is_stored(env, nft_contract_address, commitment);
}

#[test]
unconstrained fn nft_transfer_private_to_commitment_authorized_success() {
    // Setup with account contracts and mint NFT to owner
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(true, token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);

    // Prepare commitment
    let commitment = env.call_private(
        owner,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    // Verify commitment is stored
    utils::check_commitment_is_stored(env, nft_contract_address, commitment);

    // Create transfer call interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address).transfer_private_to_commitment(
        owner,
        token_id,
        commitment,
        0,
    );

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        owner,
        recipient,
        transfer_call_interface,
    );

    // Impersonate recipient to perform the authorized transfer
    env.call_private(recipient, transfer_call_interface);

    // Verify NFT is removed from owner and in commitment
    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
    // NFT should be in recipient's private set
    utils::assert_owns_private_nft(env, nft_contract_address, recipient, token_id);
    utils::check_commitment_is_stored(env, nft_contract_address, commitment);
}

#[test(should_fail_with = "nft not found in private to public")]
unconstrained fn nft_transfer_private_to_commitment_non_existent_fail() {
    // Setup but don't mint any NFT
    let (env, nft_contract_address, owner, _, recipient) = utils::setup_with_minter(false);
    let non_existent_token_id = 12345;

    // Prepare commitment as recipient
    let commitment = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, recipient),
    );

    // Attempt to transfer non-existent NFT
    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_commitment(
            owner,
            non_existent_token_id,
            commitment,
            0,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn nft_transfer_private_to_commitment_unauthorized_fail() {
    // Setup with account contracts
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(true, token_id);

    // Prepare commitment as recipient
    let commitment = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, recipient),
    );

    // Create transfer interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address).transfer_private_to_commitment(
        owner,
        token_id,
        commitment,
        1,
    );

    // Impersonate recipient but DON'T add authorization witness
    env.call_private(recipient, transfer_call_interface);
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn nft_transfer_private_to_commitment_wrong_authwit_fail() {
    // Setup with account contracts
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(true, token_id);

    // Prepare commitment as recipient
    let commitment: Field = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, recipient),
    );

    // Create transfer interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address).transfer_private_to_commitment(
        owner,
        token_id,
        commitment,
        1,
    );

    // Add authorization witness but to the wrong address (owner instead of recipient)
    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        owner,
        owner, // Wrong address - should be recipient
        transfer_call_interface,
    );

    // Impersonate recipient
    env.call_private(recipient, transfer_call_interface);
}

#[test(should_fail_with = "nft not found in private to public")]
unconstrained fn nft_transfer_private_to_commitment_public_nft_fail() {
    // Setup and mint NFT to owner in public state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_public(false, token_id);

    // Prepare commitment as recipient
    let commitment = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, recipient),
    );

    // Verify NFT is in public state
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id);

    // Attempt to transfer from private state when NFT is actually in public state
    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_commitment(owner, token_id, commitment, 0),
    );
}
