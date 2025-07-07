use crate::NFT;
use crate::test::utils;
use authwit::cheatcodes as authwit_cheatcodes;

#[test]
unconstrained fn test_burn_private() {
    // Setup accounts
    let (env, nft_contract_address, owner, minter, recipient) = utils::setup_with_minter(true);

    // Prepare multiple unique token IDs for testing
    let token_id_1 = 10000;
    let token_id_2 = 10001;

    // Mint multiple NFTs for testing different scenarios
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_1).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_2).call(&mut env.public());
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
    let non_existent_token_id = 99999;
    env.impersonate(owner);
    env.assert_private_call_fails(NFT::at(nft_contract_address).burn_private(
        owner,
        non_existent_token_id,
        0,
    ));

    // Test 3: Burn private public NFT fail
    // Verify NFT is in public state
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id_2);

    // Expected error: "nft not found in private to public"
    env.impersonate(owner);
    env.assert_private_call_fails(NFT::at(nft_contract_address).burn_private(owner, token_id_2, 0));

    let token_id_3 = 10004;
    
    // Mint NFTs for authorization tests
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_3).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Test 4: Burn private unauthorized fail
    // Create burn interface with non-zero nonce
    let burn_call_interface_unauth =
        NFT::at(nft_contract_address).burn_private(owner, token_id_3, 1);

    // Expected error: "Unknown auth witness for message hash"
    env.impersonate(recipient);
    env.assert_private_call_fails(burn_call_interface_unauth);

    // Test 5: Burn private wrong authwit fail
    // Create burn interface with non-zero nonce
    let burn_call_interface_wrong =
        NFT::at(nft_contract_address).burn_private(owner, token_id_3, 1);

    // Add authorization witness but to the wrong address (owner instead of recipient)
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient, // Wrong address - should be recipient
        burn_call_interface_wrong,
    );

    // Expected error: "Unknown auth witness for message hash"
    env.impersonate(recipient);
    env.assert_private_call_fails(burn_call_interface_wrong);

    // Test 6: Burn private authorized success
    // Verify initial state
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id_3);
    utils::assert_nft_exists(nft_contract_address, token_id_3);

    // Create burn call interface with non-zero nonce
    let burn_call_interface =
        NFT::at(nft_contract_address).burn_private(owner, token_id_3, 1);

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        burn_call_interface,
    );

    // Impersonate recipient to perform the authorized burn
    env.impersonate(recipient);
    burn_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    // Verify NFT is burned
    utils::assert_private_nft_nullified(nft_contract_address, owner, token_id_3);
    utils::assert_nft_does_not_exist(nft_contract_address, token_id_3);
}
