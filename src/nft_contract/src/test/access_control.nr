use crate::NFT;
use crate::test::utils;
use aztec::{
    oracle::{
        execution::{get_block_number, get_contract_address},
        storage::storage_read,
    },
    prelude::AztecAddress,
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
};

#[test]
unconstrained fn minter_is_set() {
    let (env, nft_contract_address, owner, minter, recipient) = utils::setup_with_minter(false);
    cheatcodes::set_contract_address(nft_contract_address);
    let minter_slot = NFT::storage_layout().minter.slot;
    let minter_address: AztecAddress = storage_read(nft_contract_address, minter_slot, get_block_number());
    // cheatcodes::set_contract_address(get_contract_address());
    assert(minter_address == minter, "minter is not set");
}
