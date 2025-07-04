use crate::NFT;
use crate::test::utils;

#[test]
unconstrained fn test_initialize_transfer_commitment() {
    // Setup without account contracts
    let (env, nft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    
    // Prepare multiple unique token IDs for testing
    let token_id_1 = 10000;
    let token_id_2 = 10001;
    let token_id_3 = 10002;
    let token_id_4 = 10003;
    
    // Mint NFTs for testing
    env.impersonate(owner);
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_1, 0).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_2, 0).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_3, 0).call(&mut env.private());
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_4, 0).call(&mut env.private());
    env.advance_block_by(1);

    // Test 1: Initialize transfer commitment success
    env.impersonate(owner);
    let commitment_1 = NFT::at(nft_contract_address)
        .initialize_transfer_commitment(owner, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify commitment is stored
    assert(utils::get_commitment_stored(nft_contract_address, commitment_1), "Commitment 1 not stored");

    // Test 2: Initialize transfer commitment by recipient success
    env.impersonate(recipient);
    let commitment_2 = NFT::at(nft_contract_address)
        .initialize_transfer_commitment(owner, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify commitment is stored
    assert(utils::get_commitment_stored(nft_contract_address, commitment_2), "Commitment 2 not stored");

    // Test 3: Initialize transfer commitment self success
    env.impersonate(owner);
    let commitment_3 = NFT::at(nft_contract_address)
        .initialize_transfer_commitment(owner, owner)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify commitment is stored
    assert(utils::get_commitment_stored(nft_contract_address, commitment_3), "Commitment 3 not stored");

    // Test 4: Initialize transfer commitment by third party success
    env.impersonate(minter);
    let commitment_4 = NFT::at(nft_contract_address)
        .initialize_transfer_commitment(owner, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify commitment is stored
    assert(utils::get_commitment_stored(nft_contract_address, commitment_4), "Commitment 4 not stored");
}
