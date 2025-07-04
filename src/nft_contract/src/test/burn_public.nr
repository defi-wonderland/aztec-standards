use crate::NFT;
use crate::test::utils;
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::prelude::AztecAddress;

#[test]
unconstrained fn test_burn_public() {
    // Setup without account contracts first
    let (env, nft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    
    // Prepare multiple unique token IDs for testing
    let token_id_1 = 10000;
    let token_id_2 = 10001;
    let non_existent_token_id = 12345;
    
    // Mint NFTs for testing
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_1).call(&mut env.public());
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    // Test 1: Burn public success
    // Verify initial state
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id_1);
    utils::assert_nft_exists(nft_contract_address, token_id_1);

    // Burn the NFT
    env.impersonate(owner);
    NFT::at(nft_contract_address).burn_public(owner, token_id_1, 0).call(&mut env.public());
    env.advance_block_by(1);

    // Verify NFT is burned (owner is zero address and NFT doesn't exist)
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id_1);
    utils::assert_nft_does_not_exist(nft_contract_address, token_id_1);

    // Test 2: Burn public non-existent fail
    // Expected error: "caller is not owner"
    env.impersonate(owner);
    env.assert_public_call_fails(
        NFT::at(nft_contract_address).burn_public(owner, non_existent_token_id, 0),
    );

    // Now setup with account contracts for authorization tests
    let (env_auth, nft_contract_address_auth, owner_auth, minter_auth, recipient_auth) = utils::setup_with_minter(true);
    
    // Mint NFTs for authorization tests
    env_auth.impersonate(minter_auth);
    NFT::at(nft_contract_address_auth).mint_to_public(owner_auth, token_id_1).call(&mut env_auth.public());
    NFT::at(nft_contract_address_auth).mint_to_public(owner_auth, token_id_2).call(&mut env_auth.public());
    env_auth.advance_block_by(1);

    // Test 3: Burn public authorized success
    // Create burn call interface with non-zero nonce
    let burn_call_interface = NFT::at(nft_contract_address_auth).burn_public(owner_auth, token_id_1, 1);

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner_auth,
        recipient_auth,
        burn_call_interface,
    );

    // Impersonate recipient to perform the authorized burn
    env_auth.impersonate(recipient_auth);
    burn_call_interface.call(&mut env_auth.public());
    env_auth.advance_block_by(1);

    // Verify NFT is burned
    utils::assert_owns_public_nft(env_auth, nft_contract_address_auth, AztecAddress::zero(), token_id_1);
    utils::assert_nft_does_not_exist(nft_contract_address_auth, token_id_1);

    // Test 4: Burn public unauthorized fail
    // Create burn interface with non-zero nonce
    let burn_call_interface_unauth = NFT::at(nft_contract_address_auth).burn_public(owner_auth, token_id_2, 1);

    // Expected error: "unauthorized"
    env_auth.impersonate(recipient_auth);
    env_auth.assert_public_call_fails(burn_call_interface_unauth);

    // Test 5: Burn public wrong authwit fail
    // Create burn interface with non-zero nonce
    let burn_call_interface_wrong = NFT::at(nft_contract_address_auth).burn_public(owner_auth, token_id_2, 1);

    // Add authorization witness but to the wrong address (owner instead of recipient)
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner_auth,
        owner_auth, // Wrong address - should be recipient
        burn_call_interface_wrong,
    );

    // Expected error: "unauthorized"
    env_auth.impersonate(recipient_auth);
    env_auth.assert_public_call_fails(burn_call_interface_wrong);
}
