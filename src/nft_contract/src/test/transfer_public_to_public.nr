use crate::NFT;
use crate::test::utils;
use authwit::cheatcodes as authwit_cheatcodes;

#[test]
unconstrained fn test_transfer_public_to_public() {
    // Setup with account contracts
    let (env, nft_contract_address, owner, minter, recipient) = utils::setup_with_minter(true);

    // Prepare multiple unique token IDs for testing
    let token_id_1 = 10000;
    let token_id_2 = 10001;
    let non_existent_token_id = 12345;

    // Mint NFTs for testing
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_1).call(&mut env.public());
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    // Test 1: Transfer public to public non-existent fail
    // Expected error: "caller is not owner"
    env.impersonate(owner);
    env.assert_public_call_fails(NFT::at(nft_contract_address).transfer_public_to_public(
        owner,
        recipient,
        non_existent_token_id,
        0,
    ));

    // Test 2: Transfer public to public unauthorized fail
    // Create transfer interface with non-zero nonce (indicating authorization needed)
    let transfer_call_interface_unauth =
        NFT::at(nft_contract_address).transfer_public_to_public(owner, recipient, token_id_2, 1);

    // Expected error: "unauthorized"
    env.impersonate(recipient);
    env.assert_public_call_fails(transfer_call_interface_unauth);

    // Test 3: Transfer public to public wrong authwit fail
    // Create transfer interface with non-zero nonce (reuse token_id_2)
    let transfer_call_interface_wrong =
        NFT::at(nft_contract_address).transfer_public_to_public(owner, recipient, token_id_2, 1);

    // Add authorization witness but to the OWNER instead of the recipient
    // This simulates giving authorization to the wrong address
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        owner, // Wrong address - should be recipient
        transfer_call_interface_wrong,
    );

    // Expected error: "unauthorized"
    env.impersonate(recipient);
    env.assert_public_call_fails(transfer_call_interface_wrong);

    // Test 4: Transfer public to public success
    // Transfer NFT from owner to recipient
    env.impersonate(owner);
    NFT::at(nft_contract_address).transfer_public_to_public(owner, recipient, token_id_1, 0).call(
        &mut env.public(),
    );
    env.advance_block_by(1);

    // Verify recipient now owns the NFT
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id_1);

    // Test 5: Transfer public to public self success
    // Transfer NFT from owner to self
    env.impersonate(owner);
    NFT::at(nft_contract_address).transfer_public_to_public(owner, owner, token_id_2, 0).call(
        &mut env.public(),
    );
    env.advance_block_by(1);

    // Verify owner still owns the NFT
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id_2);

    // Test 6: Transfer public to public authorized success
    // Need to mint a new NFT since previous tests consumed tokens
    let token_id_3 = 10002;
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_3).call(&mut env.public());
    env.advance_block_by(1);

    // Create the transfer call interface
    let transfer_call_interface =
        NFT::at(nft_contract_address).transfer_public_to_public(owner, recipient, token_id_3, 1);

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_public_authwit_from_call_interface(
        owner,
        recipient,
        transfer_call_interface,
    );

    // Impersonate recipient to perform the authorized transfer
    env.impersonate(recipient);
    transfer_call_interface.call(&mut env.public());
    env.advance_block_by(1);

    // Verify recipient now owns the NFT
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id_3);
    // Verify the NFT is no longer owned by the previous owner
    let cur_owner =
        NFT::at(nft_contract_address).public_owner_of(token_id_3).view(&mut env.public());
    assert(owner != cur_owner, "incorrect NFT owner");
}
