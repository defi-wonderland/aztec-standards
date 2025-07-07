use crate::NFT;
use crate::test::utils;
use authwit::cheatcodes as authwit_cheatcodes;

#[test]
unconstrained fn test_transfer_private_to_public_with_commitment() {
    // Setup without account contracts first
    let (env, nft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);

    // Prepare multiple unique token IDs for testing
    let token_id_1 = 10000;
    let token_id_2 = 10001;
    let token_id_3 = 10002;
    let token_id_4 = 10003;
    let non_existent_token_id = 12345;

    // Mint NFTs for testing
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_1).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_2).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_3).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_4).call(&mut env.private());
    env.advance_block_by(1);

    // Test 1: Transfer private to public with commitment success
    // Verify initial ownership
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id_1);

    // Transfer NFT with commitment
    env.impersonate(owner);
    let returned_commitment = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, token_id_1, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify ownership transfer
    utils::assert_private_nft_nullified(nft_contract_address, owner, token_id_1);
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id_1);

    // Verify commitment is stored
    assert(
        utils::get_commitment_stored(nft_contract_address, returned_commitment),
        "Commitment not stored",
    );

    // Test 2: Transfer private to public with commitment and finalize success
    // Verify initial ownership
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id_2);

    // Transfer NFT with commitment
    env.impersonate(owner);
    let commitment = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, token_id_2, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify intermediate state (public ownership and commitment)
    utils::assert_private_nft_nullified(nft_contract_address, owner, token_id_2);
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id_2);
    assert(utils::get_commitment_stored(nft_contract_address, commitment), "Commitment not stored");

    // Test 3: Transfer private to public with commitment non-existent fail
    // Expected error: "nft not found in private to public"
    env.impersonate(owner);
    env.assert_private_call_fails(NFT::at(nft_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, non_existent_token_id, 0));

    // Test 4: Finalize with invalid commitment fail
    // Transfer NFT with commitment (ignore the returned commitment)
    env.impersonate(owner);
    let _ = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, token_id_3, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Create invalid commitment
    let invalid_commitment = 0xdeadbeef;

    // Expected error: "invalid commitment"
    env.impersonate(recipient);
    env.assert_public_call_fails(NFT::at(nft_contract_address).transfer_public_to_commitment(
        recipient,
        token_id_3,
        invalid_commitment,
        0,
    ));

    // Test 5: Finalize with zero commitment fail
    // Transfer NFT with commitment (ignore the returned commitment)
    env.impersonate(owner);
    let _ = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, token_id_4, 0)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Create zero commitment
    let zero_commitment = 0;

    // Expected error: "invalid commitment"
    env.impersonate(recipient);
    env.assert_public_call_fails(NFT::at(nft_contract_address).transfer_public_to_commitment(
        recipient,
        token_id_4,
        zero_commitment,
        0,
    ));

    // Now setup with account contracts for authorization tests
    let (env_auth, nft_contract_address_auth, owner_auth, minter_auth, recipient_auth) =
        utils::setup_with_minter(true);

    // Mint NFTs for authorization tests with different token IDs
    let token_id_5 = 10004;
    env_auth.impersonate(minter_auth);
    NFT::at(nft_contract_address_auth).mint_to_private(owner_auth, token_id_5).call(
        &mut env_auth.private(),
    );
    env_auth.advance_block_by(1);

    // Test 6: Transfer private to public with commitment unauthorized fail
    // Create transfer interface with non-zero nonce
    let transfer_call_interface_unauth = NFT::at(nft_contract_address_auth)
        .transfer_private_to_public_with_commitment(owner_auth, recipient_auth, token_id_5, 1);

    // Expected error: "Unknown auth witness for message hash"
    env_auth.impersonate(recipient_auth);
    env_auth.assert_private_call_fails(transfer_call_interface_unauth);

    // Test 7: Transfer private to public with commitment authorized success
    // Verify initial ownership
    utils::assert_owns_private_nft(nft_contract_address_auth, owner_auth, token_id_5);

    // Create transfer call interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address_auth)
        .transfer_private_to_public_with_commitment(owner_auth, recipient_auth, token_id_5, 1);

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner_auth,
        recipient_auth,
        transfer_call_interface,
    );

    // Impersonate recipient to perform the authorized transfer
    env_auth.impersonate(recipient_auth);
    let returned_commitment = transfer_call_interface.call(&mut env_auth.private());
    env_auth.advance_block_by(1);

    // Verify ownership transfer
    utils::assert_private_nft_nullified(nft_contract_address_auth, owner_auth, token_id_5);
    utils::assert_owns_public_nft(
        env_auth,
        nft_contract_address_auth,
        recipient_auth,
        token_id_5,
    );

    // Verify commitment is stored
    assert(
        utils::get_commitment_stored(nft_contract_address_auth, returned_commitment),
        "Commitment not stored",
    );
}
