use crate::NFT;
use crate::test::utils;

#[test]
unconstrained fn nft_initialize_transfer_commitment_success() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize transfer commitment
    let commitment = env.call_private(
        owner,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    // Verify commitment is stored
    utils::check_commitment_is_stored(env, nft_contract_address, commitment);
}

#[test]
unconstrained fn nft_initialize_transfer_commitment_by_recipient_success() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, _, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize transfer commitment as recipient
    let commitment = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, recipient),
    );

    // Verify commitment is stored
    utils::check_commitment_is_stored(env, nft_contract_address, commitment);
}

#[test]
unconstrained fn nft_initialize_transfer_commitment_self_success() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, _) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize transfer commitment to self
    let commitment = env.call_private(
        owner,
        NFT::at(nft_contract_address).initialize_transfer_commitment(owner, owner),
    );

    // Verify commitment is stored
    utils::check_commitment_is_stored(env, nft_contract_address, commitment);
}

#[test]
unconstrained fn nft_initialize_transfer_commitment_by_third_party_success() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, _, minter, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize transfer commitment as minter (third party)
    let commitment = env.call_private(
        minter,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, minter),
    );

    // Verify commitment is stored
    utils::check_commitment_is_stored(env, nft_contract_address, commitment);
}
