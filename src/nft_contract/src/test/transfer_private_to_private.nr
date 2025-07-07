use crate::NFT;
use crate::test::utils;
use authwit::cheatcodes as authwit_cheatcodes;

#[test]
unconstrained fn test_transfer_private_to_private() {
    // Setup with account contracts
    let (env, nft_contract_address, owner, minter, recipient) = utils::setup_with_minter(true);

    // Prepare multiple unique token IDs for testing
    let token_id_1 = 10000;
    let token_id_2 = 10001;
    let token_id_3 = 10002;
    let non_existent_token_id = 12345;

    // Mint NFTs for testing
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_1).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_2).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_3).call(&mut env.public());
    env.advance_block_by(1);

    // Test 1: Transfer private to private non-existent fail
    // Expected error: "nft not found in private to public"
    env.impersonate(owner);
    env.assert_private_call_fails(NFT::at(nft_contract_address).transfer_private_to_private(
        owner,
        recipient,
        non_existent_token_id,
        0,
    ));

    // Test 2: Transfer private to private public NFT fail
    // Verify NFT is in public state
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id_3);

    // Expected error: "nft not found in private to public"
    env.impersonate(owner);
    env.assert_private_call_fails(NFT::at(nft_contract_address).transfer_private_to_private(
        owner,
        recipient,
        token_id_3,
        0,
    ));

    // Test 3: Transfer private to private unauthorized fail
    // Create transfer interface with non-zero nonce
    let transfer_call_interface_unauth = NFT::at(nft_contract_address)
        .transfer_private_to_private(owner, recipient, token_id_2, 1);

    // Expected error: "Unknown auth witness for message hash"
    env.impersonate(recipient);
    env.assert_private_call_fails(transfer_call_interface_unauth);

    // Test 4: Transfer private to private wrong authwit fail
    // Create transfer interface with non-zero nonce (reuse token_id_2)
    let transfer_call_interface_wrong = NFT::at(nft_contract_address)
        .transfer_private_to_private(owner, recipient, token_id_2, 1);

    // Add authorization witness but to the wrong address (owner instead of recipient)
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        owner, // Wrong address - should be recipient
        transfer_call_interface_wrong,
    );

    // Expected error: "Unknown auth witness for message hash"
    env.impersonate(recipient);
    env.assert_private_call_fails(transfer_call_interface_wrong);

    // Test 5: Transfer private to private success
    // Verify initial ownership
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id_1);

    // Transfer NFT from owner to recipient
    env.impersonate(owner);
    NFT::at(nft_contract_address).transfer_private_to_private(owner, recipient, token_id_1, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Verify ownership transfer
    utils::assert_private_nft_nullified(nft_contract_address, owner, token_id_1);
    utils::assert_owns_private_nft(nft_contract_address, recipient, token_id_1);

    // Test 6: Transfer private to private self success
    // Verify initial ownership
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id_2);

    // Transfer NFT from owner to self
    env.impersonate(owner);
    NFT::at(nft_contract_address).transfer_private_to_private(owner, owner, token_id_2, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Verify owner still owns the NFT
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id_2);

    // Test 7: Transfer private to private authorized success
    // Verify initial ownership
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id_2);

    // Create transfer call interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address).transfer_private_to_private(
        owner,
        recipient,
        token_id_2,
        1,
    );

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        owner,
        recipient,
        transfer_call_interface,
    );

    // Impersonate recipient to perform the authorized transfer
    env.impersonate(recipient);
    transfer_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    // Verify ownership transfer
    utils::assert_private_nft_nullified(nft_contract_address, owner, token_id_2);
    utils::assert_owns_private_nft(nft_contract_address, recipient, token_id_2);
}
