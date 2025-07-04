use crate::NFT;
use crate::test::utils;
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::prelude::AztecAddress;

#[test]
unconstrained fn test_transfer_private_to_public() {
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
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    // Test 1: Transfer private to public self success
    // Verify initial ownership state
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id_1);
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id_1);

    // Transfer NFT from private to public state (self-transfer)
    env.impersonate(owner);
    NFT::at(nft_contract_address).transfer_private_to_public(owner, owner, token_id_1, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Verify the NFT is now owned publicly by owner
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id_1);

    // Verify the NFT is no longer owned privately
    utils::assert_private_nft_nullified(nft_contract_address, owner, token_id_1);

    // Test 2: Transfer private to public non-existent NFT fail
    // Expected error: "nft not found in private to public"
    env.impersonate(owner);
    env.assert_private_call_fails(NFT::at(nft_contract_address).transfer_private_to_public(
        owner,
        recipient,
        non_existent_token_id,
        0,
    ));

    // Test 3: Transfer private to public already public fail
    // Verify NFT is in public state
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id_2);

    // Expected error: "nft not found in private to public"
    env.impersonate(owner);
    env.assert_private_call_fails(NFT::at(nft_contract_address).transfer_private_to_public(
        owner,
        recipient,
        token_id_2,
        0,
    ));

    // Now setup with account contracts for authorization tests
    let (env_auth, nft_contract_address_auth, owner_auth, _, recipient_auth) =
        utils::setup_with_minter(true);

    // Mint NFT for authorization test
    env_auth.impersonate(owner_auth);
    NFT::at(nft_contract_address_auth).mint_to_private(owner_auth, token_id_3).call(
        &mut env_auth.private(),
    );
    env_auth.advance_block_by(1);

    // Test 4: Transfer private to public authorized success
    // Verify initial ownership state
    utils::assert_owns_private_nft(nft_contract_address_auth, owner_auth, token_id_3);
    utils::assert_owns_public_nft(
        env_auth,
        nft_contract_address_auth,
        AztecAddress::zero(),
        token_id_3,
    );

    // Create the transfer call interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address_auth).transfer_private_to_public(
        owner_auth,
        recipient_auth,
        token_id_3,
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

    // Verify the NFT is now owned publicly by recipient
    utils::assert_owns_public_nft(
        env_auth,
        nft_contract_address_auth,
        recipient_auth,
        token_id_3,
    );
    utils::assert_private_nft_nullified(nft_contract_address_auth, recipient_auth, token_id_3);

    // Verify the NFT is no longer owned privately by owner
    utils::assert_private_nft_nullified(nft_contract_address_auth, owner_auth, token_id_3);

    // Test 5: Transfer private to public unauthorized fail
    // Mint another NFT for this test
    env_auth.impersonate(owner_auth);
    NFT::at(nft_contract_address_auth).mint_to_private(owner_auth, token_id_1).call(
        &mut env_auth.private(),
    );
    env_auth.advance_block_by(1);

    // Create transfer interface with non-zero nonce (indicating authorization needed)
    let transfer_call_interface_unauth = NFT::at(nft_contract_address_auth)
        .transfer_private_to_public(owner_auth, recipient_auth, token_id_1, 1);

    // Expected error: "Unknown auth witness for message hash"
    env_auth.impersonate(recipient_auth);
    env_auth.assert_private_call_fails(transfer_call_interface_unauth);
}
