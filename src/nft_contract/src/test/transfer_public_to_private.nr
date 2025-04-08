use crate::{test::utils, NFT};
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::oracle::random::random;
use std::test::OracleMock;
use crate::types::nft_note::PartialNFTNote;

#[test]
unconstrained fn transfer_public_to_private_success() {
    let (env, nft_contract_address, owner, minter, recipient) = utils::
}