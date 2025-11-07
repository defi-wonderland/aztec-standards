use crate::NFT;
use crate::test::utils;
use aztec::{protocol_types::address::AztecAddress, test::helpers::authwit as authwit_cheatcodes};

#[test]
unconstrained fn nft_transfer_private_to_public_self_success() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, _) =
        utils::setup_and_mint_to_private(false, token_id);

    // Verify initial ownership state
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id);

    // Transfer NFT from private to public state (self-transfer)
    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public(owner, owner, token_id, 0),
    );

    // Verify the NFT is now owned publicly by owner
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id);

    // Verify the NFT is no longer owned privately
    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
}

#[test]
unconstrained fn nft_transfer_private_to_public_authorized_success() {
    // Setup with account contracts (needed for authwits) and mint NFT to owner
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(true, token_id);

    // Verify initial ownership state
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id);

    // Create the transfer call interface
    let transfer_call_interface =
        NFT::at(nft_contract_address).transfer_private_to_public(owner, recipient, token_id, 0);

    // Add authorization witness from owner to recipient
    authwit_cheatcodes::add_private_authwit_from_call_interface(
        env,
        owner,
        recipient,
        transfer_call_interface,
    );

    // Impersonate recipient to perform the authorized transfer
    let _ = env.call_private(recipient, transfer_call_interface);

    // Verify the NFT is now owned publicly by recipient
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id);
    utils::assert_private_nft_nullified(env, nft_contract_address, recipient, token_id);

    // Verify the NFT is no longer owned privately by owner
    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn nft_transfer_private_to_public_unauthorized_fail() {
    // Setup with account contracts for proper authorization testing
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(true, token_id);

    // Create transfer interface with non-zero nonce (indicating authorization needed)
    let transfer_call_interface =
        NFT::at(nft_contract_address).transfer_private_to_public(owner, recipient, token_id, 0);

    // Impersonate recipient but DON'T add authorization witness
    // Should fail because recipient has no authorization witness from owner
    env.call_private(recipient, transfer_call_interface);
}

#[test(should_fail_with = "nft not found in private to public")]
unconstrained fn nft_transfer_private_to_public_non_existent_nft_fail() {
    // Setup environment but don't mint any NFT
    let (env, nft_contract_address, owner, _, recipient) = utils::setup_with_minter(false);
    let non_existent_token_id = 12345;

    // Attempt to transfer a non-existent NFT from private to public
    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public(
            owner,
            recipient,
            non_existent_token_id,
            0,
        ),
    );
}

#[test(should_fail_with = "nft not found in private to public")]
unconstrained fn nft_transfer_private_to_public_already_public_fail() {
    // Setup and mint NFT to owner in public state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_public(false, token_id);

    // Verify NFT is in public state
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id);

    // Attempt to transfer from private state when NFT is actually in public state
    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public(owner, recipient, token_id, 0),
    );
}
