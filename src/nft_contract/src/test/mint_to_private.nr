use crate::NFT;
use crate::test::utils;
use aztec::protocol::address::AztecAddress;

#[test]
unconstrained fn nft_mint_to_private_success() {
    let (env, nft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    let token_id = 10000;
    env.call_private(minter, NFT::at(nft_contract_address).mint_to_private(owner, token_id));

    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);
    // Verify no public owner exists
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id);
}

#[test(should_fail_with = "caller is not minter")]
unconstrained fn nft_mint_to_private_fail_non_minter() {
    let (env, nft_contract_address, owner, _, recipient) = utils::setup_with_minter(false);

    let token_id = 10000;
    env.call_private(recipient, NFT::at(nft_contract_address).mint_to_private(owner, token_id));
}

#[test(should_fail_with = "token already exists")]
unconstrained fn nft_mint_to_private_fail_same_nft_twice() {
    let (env, nft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    let token_id = 10000;
    let mint_call_interface = NFT::at(nft_contract_address).mint_to_private(owner, token_id);
    env.call_private(minter, mint_call_interface);

    // Verify the NFT was minted correctly
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);
    utils::assert_nft_exists(env, nft_contract_address, token_id);

    // Second call should fail
    env.call_private(minter, mint_call_interface);
}

#[test(should_fail_with = "zero token ID not supported")]
unconstrained fn nft_mint_to_private_fail_token_id_zero() {
    let (env, nft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.call_private(minter, NFT::at(nft_contract_address).mint_to_private(owner, 0));
}
