use crate::NFT;
use crate::test::utils;
use authwit::cheatcodes as authwit_cheatcodes;

#[test]
unconstrained fn test_transfer_private_to_commitment() {
    // Setup without account contracts first
    let (env, nft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);

    // Prepare multiple unique token IDs for testing
    let token_id_1 = 10000;
    let token_id_2 = 10001;
    let token_id_3 = 10002;
    let non_existent_token_id = 12345;

    // Mint NFTs for testing
    env.impersonate(owner);
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_1).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_2).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_3).call(&mut env.public());
    env.advance_block_by(1);

    // Test 1: Transfer private to commitment success
    // Verify initial ownership
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id_1);

    // Prepare commitment as recipient
    env.impersonate(recipient);
    let commitment_1: Field = NFT::at(nft_contract_address)
        .initialize_transfer_commitment(owner, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify commitment is stored
    assert(
        utils::get_commitment_stored(nft_contract_address, commitment_1),
        "Commitment not stored",
    );

    // Transfer NFT to commitment
    env.impersonate(owner);
    NFT::at(nft_contract_address)
        .transfer_private_to_commitment(owner, token_id_1, commitment_1, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify NFT is removed from owner and in commitment
    utils::assert_private_nft_nullified(nft_contract_address, owner, token_id_1);
    // NFT should not be in recipient's private set yet, only in commitment
    utils::assert_private_nft_nullified(nft_contract_address, recipient, token_id_1);
    assert(
        utils::get_commitment_stored(nft_contract_address, commitment_1),
        "Commitment not stored after transfer",
    );

    // Test 2: Transfer private to commitment non-existent fail
    // Prepare commitment as recipient
    env.impersonate(recipient);
    let commitment_2: Field = NFT::at(nft_contract_address)
        .initialize_transfer_commitment(owner, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Expected error: "nft not found in private to public"
    env.impersonate(owner);
    env.assert_private_call_fails(NFT::at(nft_contract_address).transfer_private_to_commitment(
        owner,
        non_existent_token_id,
        commitment_2,
        0,
    ));

    // Test 3: Transfer private to commitment public NFT fail
    // Prepare commitment as recipient
    env.impersonate(recipient);
    let commitment_3: Field = NFT::at(nft_contract_address)
        .initialize_transfer_commitment(owner, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify NFT is in public state
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id_3);

    // Expected error: "nft not found in private to public"
    env.impersonate(owner);
    env.assert_private_call_fails(NFT::at(nft_contract_address).transfer_private_to_commitment(
        owner,
        token_id_3,
        commitment_3,
        0,
    ));

    // Now setup with account contracts for authorization tests
    let (env_auth, nft_contract_address_auth, owner_auth, _, recipient_auth) =
        utils::setup_with_minter(true);

    // Mint NFTs for authorization tests
    env_auth.impersonate(owner_auth);
    NFT::at(nft_contract_address_auth).mint_to_private(owner_auth, token_id_1).call(
        &mut env_auth.private(),
    );
    NFT::at(nft_contract_address_auth).mint_to_private(owner_auth, token_id_2).call(
        &mut env_auth.private(),
    );
    env_auth.advance_block_by(1);

    // Test 4: Transfer private to commitment authorized success
    // Verify initial ownership
    utils::assert_owns_private_nft(nft_contract_address_auth, owner_auth, token_id_1);

    // Prepare commitment as recipient
    env_auth.impersonate(recipient_auth);
    let commitment_auth: Field = NFT::at(nft_contract_address_auth)
        .initialize_transfer_commitment(owner_auth, recipient_auth)
        .call(&mut env_auth.private());
    env_auth.advance_block_by(1);

    // Verify commitment is stored
    assert(
        utils::get_commitment_stored(nft_contract_address_auth, commitment_auth),
        "Commitment not stored",
    );

    // Create transfer call interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address_auth).transfer_private_to_commitment(
        owner_auth,
        token_id_1,
        commitment_auth,
        1,
    );

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner_auth,
        recipient_auth,
        transfer_call_interface,
    );

    // Impersonate recipient to perform the authorized transfer
    env_auth.impersonate(recipient_auth);
    transfer_call_interface.call(&mut env_auth.private());
    env_auth.advance_block_by(1);

    // Verify NFT is removed from owner and in commitment
    utils::assert_private_nft_nullified(nft_contract_address_auth, owner_auth, token_id_1);
    // NFT should not be in recipient's private set yet, only in commitment
    utils::assert_private_nft_nullified(nft_contract_address_auth, recipient_auth, token_id_1);
    assert(
        utils::get_commitment_stored(nft_contract_address_auth, commitment_auth),
        "Commitment not stored after transfer",
    );

    // Test 5: Transfer private to commitment unauthorized fail
    // Prepare commitment as recipient
    env_auth.impersonate(recipient_auth);
    let commitment_unauth: Field = NFT::at(nft_contract_address_auth)
        .initialize_transfer_commitment(owner_auth, recipient_auth)
        .call(&mut env_auth.private());
    env_auth.advance_block_by(1);

    // Create transfer interface with non-zero nonce
    let transfer_call_interface_unauth = NFT::at(nft_contract_address_auth)
        .transfer_private_to_commitment(owner_auth, token_id_2, commitment_unauth, 1);

    // Expected error: "Unknown auth witness for message hash"
    env_auth.impersonate(recipient_auth);
    env_auth.assert_private_call_fails(transfer_call_interface_unauth);

    // Test 6: Transfer private to commitment wrong authwit fail
    // Create transfer interface with non-zero nonce
    let transfer_call_interface_wrong = NFT::at(nft_contract_address_auth)
        .transfer_private_to_commitment(owner_auth, token_id_2, commitment_unauth, 1);

    // Add authorization witness but to the wrong address (owner instead of recipient)
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner_auth,
        owner_auth, // Wrong address - should be recipient
        transfer_call_interface_wrong,
    );

    // Expected error: "Unknown auth witness for message hash"
    env_auth.impersonate(recipient_auth);
    env_auth.assert_private_call_fails(transfer_call_interface_wrong);
}
