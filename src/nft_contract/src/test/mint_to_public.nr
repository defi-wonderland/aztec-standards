use crate::NFT;
use crate::test::utils;

#[test]
unconstrained fn mint_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, nft_contract_address, owner, minter, _) = utils::setup_with_minter(/* with_account_contracts */ false);
    let token_id = 10000;

    env.impersonate(minter);
    NFT::at(nft_contract_address).mint(owner, token_id).call(&mut env.public());

    env.advance_block_by(1);

    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id);
}

#[test]
unconstrained fn mint_fail_non_minter() {
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_with_minter(/* with_account_contracts */ false);

    // MINTING AS A NON-MINTER
    let token_id = 10000;
    env.impersonate(recipient);
    let mint_call_interface = NFT::at(nft_contract_address).mint(owner, token_id);
    env.assert_public_call_fails(mint_call_interface);

    assert(!utils::get_nft_exists(nft_contract_address, token_id), "NFT minted by non-minter");
}

#[test]
unconstrained fn mint_fail_same_nft_twice() {
    let (env, nft_contract_address, owner, minter, recipient) =
        utils::setup_with_minter(/* with_account_contracts */ false);

    // MINTING THE SAME NFT TWICE
    let token_id = 10000;
    env.impersonate(minter);
    let mint_call_interface = NFT::at(nft_contract_address).mint(owner, token_id);
    mint_call_interface.call(&mut env.public());
    
    // Get the owner and check it matches
    let actual_owner = NFT::at(nft_contract_address).owner_of(token_id).view(&mut env.public());
    assert(actual_owner == owner, "NFT not minted to correct owner");
    
    assert(utils::get_nft_exists(nft_contract_address, token_id), "NFT not minted");

    // Second call should fail
    env.assert_public_call_fails(mint_call_interface);
}

#[test]
unconstrained fn mint_fail_token_id_zero() {
    let (env, nft_contract_address, owner, minter, _) =
        utils::setup_with_minter(/* with_account_contracts */ false);

    // MINTING NFT WITH TOKEN ID 0
    let token_id = 10000;
    env.impersonate(owner);
    let mint_call_interface = NFT::at(nft_contract_address).mint(owner, 0);
    env.assert_public_call_fails(mint_call_interface);
}
