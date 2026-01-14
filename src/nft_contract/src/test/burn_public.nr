use crate::NFT;
use crate::test::utils;
use aztec::{protocol_types::address::AztecAddress, test::helpers::authwit as authwit_cheatcodes};

#[test]
unconstrained fn nft_burn_public_success() {
    // Setup and mint NFT to owner in public state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, _) = utils::setup_and_mint_to_public(false, token_id);

    // Verify initial state
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id);
    utils::assert_nft_exists(env, nft_contract_address, token_id);

    // Burn the NFT
    env.call_public(owner, NFT::at(nft_contract_address).burn_public(owner, token_id, 0));

    // Verify NFT is burned (owner is zero address and NFT doesn't exist)
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id);
    utils::assert_nft_does_not_exist(env, nft_contract_address, token_id);
}

#[test]
unconstrained fn nft_burn_public_authorized_success() {
    // Setup with account contracts and mint NFT to owner
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_public(true, token_id);

    // Create burn call interface with non-zero nonce
    let burn_call_interface = NFT::at(nft_contract_address).burn_public(owner, token_id, 1);

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_public_authwit_from_call(env, owner, recipient, burn_call_interface);

    // Impersonate recipient to perform the authorized burn
    env.call_public(recipient, burn_call_interface);

    // Verify NFT is burned
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id);
    utils::assert_nft_does_not_exist(env, nft_contract_address, token_id);
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn nft_burn_public_unauthorized_fail() {
    // Setup with account contracts
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_public(true, token_id);

    // Create burn interface with non-zero nonce
    let burn_call_interface = NFT::at(nft_contract_address).burn_public(owner, token_id, 1);

    // Impersonate recipient but DON'T add authorization witness
    env.call_public(recipient, burn_call_interface);
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn nft_burn_public_wrong_authwit_fail() {
    // Setup with account contracts
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_public(true, token_id);

    // Create burn interface with non-zero nonce
    let burn_call_interface = NFT::at(nft_contract_address).burn_public(owner, token_id, 1);

    // Add authorization witness but to the wrong address (owner instead of recipient)
    authwit_cheatcodes::add_public_authwit_from_call(
        env,
        owner,
        owner, // Wrong address - should be recipient
        burn_call_interface,
    );

    // Impersonate recipient
    env.call_public(recipient, burn_call_interface);
}

#[test(should_fail_with = "caller is not owner")]
unconstrained fn nft_burn_public_non_existent_fail() {
    // Setup but don't mint any NFT
    let (env, nft_contract_address, owner, _, _) = utils::setup_with_minter(false);
    let non_existent_token_id = 12345;

    // Attempt to burn non-existent NFT
    env.call_public(
        owner,
        NFT::at(nft_contract_address).burn_public(owner, non_existent_token_id, 0),
    );
}
