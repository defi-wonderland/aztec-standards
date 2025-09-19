use crate::NFT;
use crate::test::utils;

#[test]
unconstrained fn nft_mint_to_public_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, nft_contract_address, owner, minter, _) = utils::setup_with_minter(false);
    let token_id = 10000;

    env.call_public(minter, NFT::at(nft_contract_address).mint_to_public(owner, token_id));

    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id);
}

#[test(should_fail_with = "caller is not minter")]
unconstrained fn nft_mint_to_public_fail_non_minter() {
    let (env, nft_contract_address, owner, _, recipient) = utils::setup_with_minter(false);

    let token_id = 10000;
    env.call_public(recipient, NFT::at(nft_contract_address).mint_to_public(owner, token_id));
}

#[test(should_fail_with = "token already exists")]
unconstrained fn nft_mint_to_public_fail_same_nft_twice() {
    let (env, nft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    let token_id = 10000;
    let mint_call_interface = NFT::at(nft_contract_address).mint_to_public(owner, token_id);
    env.call_public(minter, mint_call_interface);

    let actual_owner = env.view_public(NFT::at(nft_contract_address).public_owner_of(token_id));
    assert(actual_owner == owner, "NFT not minted to correct owner");

    utils::assert_nft_exists(env, nft_contract_address, token_id);

    // Second call should fail
    env.call_public(minter, mint_call_interface);
}

#[test(should_fail_with = "zero token ID not supported")]
unconstrained fn nft_mint_to_public_fail_token_id_zero() {
    let (env, nft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.call_public(minter, NFT::at(nft_contract_address).mint_to_public(owner, 0));
}
