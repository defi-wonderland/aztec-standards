use crate::NFT;
use crate::test::utils;
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::prelude::AztecAddress;

#[test]
unconstrained fn test_transfer_public_to_private() {
    // Setup with account contracts
    let (env, nft_contract_address, owner, minter, recipient) = utils::setup_with_minter(true);

    // Prepare multiple unique token IDs for testing
    let token_id_1 = 10000;
    let token_id_2 = 10001;
    let non_existent_token_id = 12345;

    // Mint NFTs for testing
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    // Test 1: Transfer public to private not owned fail
    // Expected error: "caller is not owner"
    env.impersonate(owner);
    env.assert_private_call_fails(NFT::at(nft_contract_address).transfer_public_to_private(
        owner,
        recipient,
        non_existent_token_id,
        0,
    ));

    // Test 2: Transfer public to private unauthorized fail
    // Create transfer interface with non-zero nonce (indicating authorization needed)
    let transfer_call_interface_unauth = NFT::at(nft_contract_address)
        .transfer_public_to_private(owner, recipient, token_id_2, 1);

    // Expected error: "Unknown auth witness for message hash"
    env.impersonate(recipient);
    env.assert_private_call_fails(transfer_call_interface_unauth);

    // Test 3: Transfer public to private success
    // Verify initial ownership state
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id_1);

    // Transfer NFT from public to private state
    env.impersonate(owner);
    NFT::at(nft_contract_address).transfer_public_to_private(owner, recipient, token_id_1, 0).call(
        &mut env.private(),
    );
    env.advance_block_by(1);

    // Verify the NFT is no longer owned publicly by owner
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id_1);
    // Verify the NFT is now owned privately by recipient
    utils::assert_owns_private_nft(nft_contract_address, recipient, token_id_1);

    // Test 4: Transfer public to private authorized success
    // Need to mint a new NFT since token_id_1 was consumed in the success test
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_2).call(&mut env.public());
    env.advance_block_by(1);

    // Create the transfer call interface
    let transfer_call_interface = NFT::at(nft_contract_address).transfer_public_to_private(
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

    // Verify the NFT is no longer owned publicly by owner
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id_2);
    // Verify the NFT is now owned privately by recipient
    utils::assert_owns_private_nft(nft_contract_address, recipient, token_id_2);
}
