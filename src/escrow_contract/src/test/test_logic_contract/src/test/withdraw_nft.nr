use crate::test::utils as logic_utils;
use crate::TestLogic;
use nft::{NFT, test::utils as nft_utils};

// TODO: add test for successful withdraws via the logic contract. Currently it is not possible
// because the address cannot be set in the salt nor we cannot modify the logic address to be the salt

#[test(should_fail_with = "Not Authorized")]
unconstrained fn withdraw_unauthorized() {
    let (env, escrow, _, nft, _, recipient, minter) =
        logic_utils::set_escrow_with_token_and_nft(false, 1);

    // Mint some tokens to escrow
    let token_id: Field = 1;
    env.impersonate(minter);
    NFT::at(nft).mint_to_private(escrow, token_id).call(&mut env.private());
    env.advance_block_by(1);
    // Check the escrow received and can read the nft
    nft_utils::assert_owns_private_nft(nft, escrow, token_id);

    let logic = logic_utils::deploy_logic(env, 1);

    TestLogic::at(logic).withdraw_nft(escrow, recipient, nft, token_id).call(&mut env.private());
}
