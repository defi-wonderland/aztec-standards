use crate::NFT;
use crate::test::utils;
use aztec::prelude::AztecAddress;
use aztec::protocol_types::{hash::poseidon2_hash_with_separator, traits::FromField};

pub global PRIVATE_OWNER_ADDRESS: AztecAddress = AztecAddress::from_field(
    poseidon2_hash_with_separator([0x1234567890abcdef], 0x1234567890abcdef), // "PRIVATE_OWNER" and "NFT_PRIVATE_OWNER" separator
);

#[test]
unconstrained fn nft_mint_to_private_success() {
    let (env, nft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    let token_id = 10000;
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_private(owner, token_id).call(&mut env.private());
    env.advance_block_by(1);

    utils::assert_owns_private_nft(nft_contract_address, owner, token_id);
    // Verify no public owner exists
    utils::assert_owns_public_nft(env, nft_contract_address, PRIVATE_OWNER_ADDRESS, token_id);
}

#[test(should_fail_with = "caller is not minter")]
unconstrained fn nft_mint_to_private_fail_non_minter() {
    let (env, nft_contract_address, owner, _, recipient) = utils::setup_with_minter(false);

    let token_id = 10000;
    env.impersonate(recipient);
    NFT::at(nft_contract_address).mint_to_private(owner, token_id).call(&mut env.private());
}

#[test(should_fail_with = "token already exists")]
unconstrained fn nft_mint_to_private_fail_same_nft_twice() {
    let (env, nft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    let token_id = 10000;
    env.impersonate(minter);
    let mint_call_interface = NFT::at(nft_contract_address).mint_to_private(owner, token_id);
    mint_call_interface.call(&mut env.private());
    env.advance_block_by(1);

    // Verify the NFT was minted correctly
    utils::assert_owns_private_nft(nft_contract_address, owner, token_id);
    utils::assert_nft_exists(nft_contract_address, token_id);

    // Second call should fail
    mint_call_interface.call(&mut env.private());
}

#[test(should_fail_with = "zero token ID not supported")]
unconstrained fn nft_mint_to_private_fail_token_id_zero() {
    let (env, nft_contract_address, owner, minter, _) = utils::setup_with_minter(false);

    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_private(owner, 0).call(&mut env.private());
}
