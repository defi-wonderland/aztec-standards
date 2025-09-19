use crate::NFT;
use crate::test::utils;
use aztec::{
    oracle::{execution::get_block_number, storage::storage_read},
    protocol_types::address::AztecAddress,
    test::helpers::txe_oracles as cheatcodes,
};

#[test]
unconstrained fn nft_minter_is_set() {
    let (env, nft_contract_address, _, minter, _) = utils::setup_with_minter(false);
     env.public_context_at(nft_contract_address, |context| {
        let minter_address = context.storage_read(NFT::storage_layout().minter.slot);
        assert(minter_address == minter, "minter is not set");
    });
}
