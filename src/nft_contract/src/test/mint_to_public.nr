use crate::NFT;
use crate::test::utils;

#[test]
unconstrained fn mint_success() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, nft_contract_address, owner, minter, _) =
        utils::setup_with_minter(/* with_account_contracts */ false);
    let token_id = 10000;

    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_public(owner, token_id).call(&mut env.public());

    env.advance_block_by(1);

    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id);
}

#[test(should_fail_with = "caller is not minter")]
unconstrained fn mint_fail_non_minter() {
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_with_minter(/* with_account_contracts */ false);

    let token_id = 10000;
    env.impersonate(recipient);
    let mint_call_interface = NFT::at(nft_contract_address).mint_public(owner, token_id).call(&mut env.public());
}

#[test(should_fail_with = "token already exists")]
unconstrained fn mint_fail_same_nft_twice() {
    let (env, nft_contract_address, owner, minter, recipient) =
        utils::setup_with_minter(/* with_account_contracts */ false);

    let token_id = 10000;
    env.impersonate(minter);
    let mint_call_interface = NFT::at(nft_contract_address).mint_public(owner, token_id);
    mint_call_interface.call(&mut env.public());

    let actual_owner = NFT::at(nft_contract_address).public_owner_of(token_id).view(&mut env.public());
    assert(actual_owner == owner, "NFT not minted to correct owner");

    assert(utils::get_nft_exists(nft_contract_address, token_id) == true, "NFT not minted");

    // Second call should fail
    mint_call_interface.call(&mut env.public());
}

#[test(should_fail_with = "zero token ID not supported")]
unconstrained fn mint_fail_token_id_zero() {
    let (env, nft_contract_address, owner, minter, _) =
        utils::setup_with_minter(/* with_account_contracts */ false);

    let token_id = 10000;
    env.impersonate(minter);
    let mint_call_interface = NFT::at(nft_contract_address).mint_public(owner, 0).call(&mut env.public());
}
