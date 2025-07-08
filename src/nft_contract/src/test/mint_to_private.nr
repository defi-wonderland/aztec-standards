use crate::NFT;
use crate::test::utils;
use aztec::prelude::AztecAddress;

#[test]
unconstrained fn test_mint_to_private() {
    // Setup with account contracts
    let (env, nft_contract_address, owner, minter, recipient) = utils::setup_with_minter(true);

    // Prepare multiple unique token IDs for testing
    let token_id_1 = 10000;

    // Test 1: Mint to private fail non-minter
    // Expected error: "caller is not minter"
    env.impersonate(recipient);
    env.assert_private_call_fails(NFT::at(nft_contract_address).mint_to_private(owner, token_id_2));

    // Test 2: Mint to private fail token ID zero
    // Expected error: "zero token ID not supported"
    env.impersonate(minter);
    env.assert_private_call_fails(NFT::at(nft_contract_address).mint_to_private(owner, 0));

    // Test 3: Mint to private success
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_private(owner, token_id_1).call(&mut env.private());
    env.advance_block_by(1);

    utils::assert_owns_private_nft(nft_contract_address, owner, token_id_1);
    // Verify no public owner exists
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id_1);

    // Test 4: Mint to private fail same NFT twice
    env.impersonate(minter);
    let mint_call_interface = NFT::at(nft_contract_address).mint_to_private(owner, token_id_1);
    
    // Expected error: "token already exists"
    env.assert_private_call_fails(mint_call_interface);
}
