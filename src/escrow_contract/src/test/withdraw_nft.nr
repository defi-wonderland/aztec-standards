use crate::Escrow;
use crate::test::utils as escrow_utils;
use nft::{NFT, test::utils as nft_utils};

// TODO (reenable test): TXE scope enforcement means only the `from` address's notes are accessible during
// private execution. The escrow's NFT notes are not in scope when called from logic_contract_address.
// The TS tests handle this via `additionalScopes: [escrow.address]`, but TXE doesn't support it yet.
// See: https://github.com/AztecProtocol/aztec-packages/blob/v4.2.0-aztecnr-rc.2/noir-projects/aztec-nr/aztec/src/test/helpers/test_environment.nr#L953-L954
#[allow(dead_code)]
unconstrained fn escrow_withdraw_nft_success() {
    let escrow_secret: Field = 123456;
    let (mut env, escrow_contract_address, _, nft_contract_address, _, recipient, minter, logic_contract_address) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    // Mint NFT to escrow
    let token_id: Field = 1;
    env.call_private(
        minter,
        NFT::at(nft_contract_address).mint_to_private(escrow_contract_address, token_id),
    );

    // Check the escrow received and can read the nft
    nft_utils::assert_owns_private_nft(
        env,
        nft_contract_address,
        escrow_contract_address,
        token_id,
    );

    env.call_private(
        logic_contract_address,
        Escrow::at(escrow_contract_address).withdraw_nft(nft_contract_address, token_id, recipient),
    );

    // Check recipient got tokens
    nft_utils::assert_owns_private_nft(env, nft_contract_address, recipient, token_id);
}

#[test(should_fail_with = "Not Authorized")]
unconstrained fn escrow_withdraw_nft_unauthorized() {
    let escrow_secret: Field = 123456;
    let (mut env, escrow_contract_address, _, nft_contract_address, owner, recipient, _, _) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    let token_id: Field = 1;
    env.call_private(
        owner,
        Escrow::at(escrow_contract_address).withdraw_nft(nft_contract_address, token_id, recipient),
    );
}
