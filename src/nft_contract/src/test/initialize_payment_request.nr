use crate::NFT;
use crate::test::utils;

#[test]
unconstrained fn nft_initialize_payment_request_success() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize payment request
    env.impersonate(owner);
    let payment_request = NFT::at(nft_contract_address)
        .initialize_payment_request(owner, recipient, owner)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify payment request is stored
    assert(
        utils::get_commitment_stored(nft_contract_address, payment_request),
        "Payment request not stored",
    );
}

#[test]
unconstrained fn nft_initialize_payment_request_by_recipient_success() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize payment request as recipient
    env.impersonate(recipient);
    let payment_request = NFT::at(nft_contract_address)
        .initialize_payment_request(owner, recipient, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify payment request is stored
    assert(
        utils::get_commitment_stored(nft_contract_address, payment_request),
        "Payment request not stored",
    );
}

#[test]
unconstrained fn nft_initialize_payment_request_self_success() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, _) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize payment request to self
    env.impersonate(owner);
    let payment_request = NFT::at(nft_contract_address)
        .initialize_payment_request(owner, owner, owner)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify payment request is stored
    assert(
        utils::get_commitment_stored(nft_contract_address, payment_request),
        "Payment request not stored",
    );
}

#[test]
unconstrained fn nft_initialize_payment_request_by_third_party_success() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, minter, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize payment request as minter (third party)
    env.impersonate(minter);
    let payment_request = NFT::at(nft_contract_address)
        .initialize_payment_request(owner, recipient, minter)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Verify payment request is stored
    assert(
        utils::get_commitment_stored(nft_contract_address, payment_request),
        "Payment request not stored",
    );
}
