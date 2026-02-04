use crate::NFT;
use aztec::{
    protocol::{address::AztecAddress, storage::map::derive_storage_slot_in_map},
    test::helpers::test_environment::TestEnvironment,
};

pub unconstrained fn setup_with_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let (owner, minter, recipient) = if with_account_contracts {
        let owner = env.create_contract_account();
        let minter = env.create_contract_account();
        let recipient = env.create_contract_account();
        (owner, minter, recipient)
    } else {
        // For simple tests without authorization, use regular accounts
        let owner = env.create_light_account();
        let minter = env.create_light_account();
        let recipient = env.create_light_account();
        (owner, minter, recipient)
    };

    let nft_contract_address = deploy_nft_with_minter(&mut env, owner, minter);

    (env, nft_contract_address, owner, minter, recipient)
}

pub unconstrained fn deploy_nft_with_minter(
    env: &mut TestEnvironment,
    owner: AztecAddress,
    minter: AztecAddress,
) -> AztecAddress {
    // Deploy token contract
    let initializer_call_interface = NFT::interface().constructor_with_minter(
        "TestNFT000000000000000000000000",
        "TNFT000000000000000000000000000",
        minter,
        AztecAddress::zero(),
    );
    let nft_contract_address =
        env.deploy("@nft_contract/NFT").with_public_initializer(owner, initializer_call_interface);

    nft_contract_address
}

/// @dev Setup and mint to owner in public
pub unconstrained fn setup_and_mint_to_public(
    with_account_contracts: bool,
    token_id: Field,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (env, nft_contract_address, owner, minter, recipient) =
        setup_with_minter(with_account_contracts);

    env.call_public(minter, NFT::at(nft_contract_address).mint_to_public(owner, token_id));

    (env, nft_contract_address, owner, minter, recipient)
}

pub unconstrained fn setup_and_mint_to_private(
    with_account_contracts: bool,
    token_id: Field,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (env, nft_contract_address, owner, minter, recipient) =
        setup_with_minter(with_account_contracts);

    env.call_private(minter, NFT::at(nft_contract_address).mint_to_private(owner, token_id));

    (env, nft_contract_address, owner, minter, recipient)
}

pub unconstrained fn assert_nft_exists(
    env: TestEnvironment,
    nft_contract_address: AztecAddress,
    token_id: Field,
) {
    env.public_context_at(nft_contract_address, |context| {
        let nft_exists_slot = NFT::storage_layout().nft_exists.slot;
        let nft_slot = derive_storage_slot_in_map(nft_exists_slot, token_id);
        let nft_exists = context.storage_read(nft_slot);
        assert(nft_exists, "NFT does not exist");
    });
}

pub unconstrained fn assert_nft_does_not_exist(
    env: TestEnvironment,
    nft_contract_address: AztecAddress,
    token_id: Field,
) {
    env.public_context_at(nft_contract_address, |context| {
        let nft_exists_slot = NFT::storage_layout().nft_exists.slot;
        let nft_slot = derive_storage_slot_in_map(nft_exists_slot, token_id);
        let nft_exists = context.storage_read(nft_slot);
        assert(!nft_exists, "NFT exists when it should not");
    });
}

pub unconstrained fn assert_owns_public_nft(
    env: TestEnvironment,
    nft_contract_address: AztecAddress,
    owner: AztecAddress,
    token_id: Field,
) {
    let obtained_owner = env.view_public(NFT::at(nft_contract_address).public_owner_of(token_id));
    assert(owner == obtained_owner, "incorrect NFT owner");
}

pub unconstrained fn assert_owns_private_nft(
    env: TestEnvironment,
    nft_contract_address: AztecAddress,
    owner: AztecAddress,
    token_id: Field,
) {
    let nft_found = owns_private_nft(env, nft_contract_address, owner, token_id);
    assert(nft_found, "NFT not found in private nfts");
}

pub unconstrained fn assert_private_nft_nullified(
    env: TestEnvironment,
    nft_contract_address: AztecAddress,
    owner: AztecAddress,
    token_id: Field,
) {
    let nft_found = owns_private_nft(env, nft_contract_address, owner, token_id);
    assert(!nft_found, "NFT found in private notes when it should have been nullified");
}

pub unconstrained fn owns_private_nft(
    env: TestEnvironment,
    nft_contract_address: AztecAddress,
    owner: AztecAddress,
    token_id: Field,
) -> bool {
    // Direct call to unconstrained
    let (private_nfts, _) =
        env.simulate_utility(NFT::at(nft_contract_address).get_private_nfts(owner, 0));

    let mut nft_found = false;
    for obtained_token_id in private_nfts {
        if obtained_token_id == token_id {
            nft_found = true;
        }
    }
    nft_found
}

pub unconstrained fn check_commitment_is_stored(
    env: TestEnvironment,
    nft_contract_address: AztecAddress,
    commitment: Field,
) {
    env.public_context_at(nft_contract_address, |context| {
        let stored = context.storage_read(commitment);
        assert_eq(stored, true);
    });
}
