use crate::NFT;
use crate::test::utils;
use aztec::prelude::AztecAddress;

#[test]
unconstrained fn mint_private_success() {
    let (env, nft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);

    let token_id = 10000;
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_private(owner, token_id).call(&mut env.private());
    env.advance_block_by(1);

    utils::assert_owns_private_nft(nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id);
}
