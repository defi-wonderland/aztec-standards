use crate::Escrow;
use crate::test::utils as escrow_utils;
use aztec::oracle::get_contract_instance::get_contract_instance;
use aztec::prelude::AztecAddress;
use aztec::protocol_types::traits::FromField;
use nft::{NFT, test::utils as nft_utils};

#[test]
unconstrained fn escrow_withdraw_nft_success() {
    let escrow_secret: Field = 123456;
    let (env, escrow_contract_address, _, nft_contract_address, _, recipient, minter) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    let escrow_instance = get_contract_instance(escrow_contract_address);
    let logic_contract_address = AztecAddress::from_field(escrow_instance.salt);

    // Mint some tokens to escrow
    let token_id: Field = 1;
    env.impersonate(minter);
    NFT::at(nft_contract_address).mint_to_private(escrow_contract_address, token_id).call(
        &mut env.private(),
    );
    env.advance_block_by(1);
    // Check the escrow received and can read the nft
    nft_utils::assert_owns_private_nft(nft_contract_address, escrow_contract_address, token_id);

    env.impersonate(logic_contract_address);
    Escrow::at(escrow_contract_address)
        .withdraw_nft(nft_contract_address, token_id, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);

    // Check recipient got tokens
    nft_utils::assert_owns_private_nft(nft_contract_address, recipient, token_id);
}

#[test(should_fail_with = "Not Authorized")]
unconstrained fn escrow_withdraw_nft_unauthorized() {
    let escrow_secret: Field = 123456;
    let (env, escrow_contract_address, _, nft_contract_address, owner, recipient, _) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    let escrow_instance = get_contract_instance(escrow_contract_address);
    let logic_contract_address = AztecAddress::from_field(escrow_instance.salt);

    let token_id: Field = 1;
    env.impersonate(owner);
    Escrow::at(escrow_contract_address)
        .withdraw_nft(nft_contract_address, token_id, recipient)
        .call(&mut env.private());
    env.advance_block_by(1);
}
