use crate::NFT;
use crate::test::utils;

#[test]
unconstrained fn test_mint_to_public() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, nft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);

    // Prepare multiple unique token IDs for testing
    let token_id_1 = 10000;
    let token_id_2 = 10001;

    // Test 1: Mint to public success
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_public(owner, token_id_1).call(&mut env.public());
    env.advance_block_by(1);

    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id_1);

    // Test 2: Mint to public fail non-minter
    // Expected error: "caller is not minter"
    env.impersonate(recipient);
    env.assert_public_call_fails(NFT::at(nft_contract_address).mint_to_public(owner, token_id_2));

    // Test 3: Mint to public fail same NFT twice
    env.impersonate(minter);
    let mint_call_interface = NFT::at(nft_contract_address).mint_to_public(owner, token_id_2);
    mint_call_interface.call(&mut env.public());

    let actual_owner =
        NFT::at(nft_contract_address).public_owner_of(token_id_2).view(&mut env.public());
    assert(actual_owner == owner, "NFT not minted to correct owner");

    utils::assert_nft_exists(nft_contract_address, token_id_2);

    // Expected error: "token already exists"
    env.assert_public_call_fails(mint_call_interface);

    // Test 4: Mint to public fail token ID zero
    // Expected error: "zero token ID not supported"
    env.impersonate(minter);
    env.assert_public_call_fails(NFT::at(nft_contract_address).mint_to_public(owner, 0));
}
