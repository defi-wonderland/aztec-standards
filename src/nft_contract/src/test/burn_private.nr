use crate::NFT;
use crate::test::utils;
use authwit::cheatcodes as authwit_cheatcodes;

#[test]
unconstrained fn test_burn_private() {
    // Setup without account contracts first
    let (env, nft_contract_address, owner, _, recipient) = utils::setup_with_minter(false);
    
    // Prepare multiple unique token IDs for testing
    let token_id_1 = 10000;
    let token_id_2 = 10001;
    let token_id_3 = 10002;
    let token_id_4 = 10003;
    let non_existent_token_id = 12345;
    
    // Mint multiple NFTs for testing different scenarios
    env.impersonate(owner);
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_1, 0).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_2, 0).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_3, 0).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_4).call(&mut env.public());
    env.advance_block_by(1);

    // Test 1: Burn private self success
    // Verify initial state
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id_1);
    utils::assert_nft_exists(nft_contract_address, token_id_1);

    // Burn the NFT
    env.impersonate(owner);
    NFT::at(nft_contract_address).burn_private(owner, token_id_1, 0).call(&mut env.private());
    env.advance_block_by(1);

    // Verify NFT is burned (no longer in private notes and marked as non-existent)
    utils::assert_private_nft_nullified(nft_contract_address, owner, token_id_1);
    utils::assert_nft_does_not_exist(nft_contract_address, token_id_1);

    // Test 2: Burn private non-existent fail
    // Expected error: "nft not found in private to public"
    env.impersonate(owner);
    env.assert_private_call_fails(
        NFT::at(nft_contract_address).burn_private(owner, non_existent_token_id, 0),
    );

    // Test 3: Burn private public NFT fail
    // Verify NFT is in public state
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id_4);
    
    // Expected error: "nft not found in private to public"
    env.impersonate(owner);
    env.assert_private_call_fails(
        NFT::at(nft_contract_address).burn_private(owner, token_id_4, 0),
    );

    // Now setup with account contracts for authorization tests
    let (env_auth, nft_contract_address_auth, owner_auth, _, recipient_auth) = utils::setup_with_minter(true);
    
    // Mint NFTs for authorization tests
    env_auth.impersonate(owner_auth);
    NFT::at(nft_contract_address_auth).mint_to_private(owner_auth, token_id_1, 0).call(&mut env_auth.private());
    NFT::at(nft_contract_address_auth).mint_to_private(owner_auth, token_id_2, 0).call(&mut env_auth.private());
    NFT::at(nft_contract_address_auth).mint_to_private(owner_auth, token_id_3, 0).call(&mut env_auth.private());
    env_auth.advance_block_by(1);

    // Test 4: Burn private authorized success
    // Verify initial state
    utils::assert_owns_private_nft(nft_contract_address_auth, owner_auth, token_id_1);
    utils::assert_nft_exists(nft_contract_address_auth, token_id_1);

    // Create burn call interface with non-zero nonce
    let burn_call_interface = NFT::at(nft_contract_address_auth).burn_private(owner_auth, token_id_1, 1);

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner_auth,
        recipient_auth,
        burn_call_interface,
    );

    // Impersonate recipient to perform the authorized burn
    env_auth.impersonate(recipient_auth);
    burn_call_interface.call(&mut env_auth.private());
    env_auth.advance_block_by(1);

    // Verify NFT is burned
    utils::assert_private_nft_nullified(nft_contract_address_auth, owner_auth, token_id_1);
    utils::assert_nft_does_not_exist(nft_contract_address_auth, token_id_1);

    // Test 5: Burn private unauthorized fail
    // Create burn interface with non-zero nonce
    let burn_call_interface_unauth = NFT::at(nft_contract_address_auth).burn_private(owner_auth, token_id_2, 1);

    // Expected error: "Unknown auth witness for message hash"
    env_auth.impersonate(recipient_auth);
    env_auth.assert_private_call_fails(burn_call_interface_unauth);

    // Test 6: Burn private wrong authwit fail
    // Create burn interface with non-zero nonce
    let burn_call_interface_wrong = NFT::at(nft_contract_address_auth).burn_private(owner_auth, token_id_3, 1);

    // Add authorization witness but to the wrong address (owner instead of recipient)
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner_auth,
        owner_auth, // Wrong address - should be recipient
        burn_call_interface_wrong,
    );

    // Expected error: "Unknown auth witness for message hash"
    env_auth.impersonate(recipient_auth);
    env_auth.assert_private_call_fails(burn_call_interface_wrong);
}
