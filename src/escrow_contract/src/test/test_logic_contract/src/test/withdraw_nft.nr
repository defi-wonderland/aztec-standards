use crate::test::utils as logic_utils;
use crate::TestLogic;
use aztec::test::helpers::test_environment::{CallPrivateOptions, TestEnvironment};
use escrow_contract::test::utils as escrow_utils;
use nft::{NFT, test::utils as nft_utils};

#[test]
unconstrained fn withdraw_nft_success() {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();
    let recipient = env.create_light_account();
    let minter = env.create_light_account();

    let nft = nft_utils::deploy_nft_with_minter(&mut env, owner, minter);

    let escrow_class_id = escrow_utils::get_escrow_class_id();
    let logic = logic_utils::deploy_logic(&mut env, escrow_class_id);
    let escrow = escrow_utils::deploy_escrow_with_secret(&mut env, 1, logic);

    // Mint NFT to escrow
    let token_id: Field = 1;
    env.call_private(minter, NFT::at(nft).mint_to_private(escrow, token_id));

    // Check the escrow received and can read the NFT
    nft_utils::assert_owns_private_nft(env, nft, escrow, token_id);

    let caller = env.create_light_account();
    env.call_private_opts(
        caller,
        CallPrivateOptions::new().with_additional_scopes([escrow]),
        TestLogic::at(logic).withdraw_nft(escrow, recipient, nft, token_id),
    );

    // Check recipient got NFT
    nft_utils::assert_owns_private_nft(env, nft, recipient, token_id);
}

#[test(should_fail_with = "Not Authorized")]
unconstrained fn withdraw_unauthorized() {
    let (mut env, escrow, _, nft, _, recipient, minter, _) =
        escrow_utils::set_escrow_with_token_and_nft(false, 1);

    // Mint NFT to escrow
    let token_id: Field = 1;
    env.call_private(minter, NFT::at(nft).mint_to_private(escrow, token_id));

    // Check the escrow received and can read the NFT
    nft_utils::assert_owns_private_nft(env, nft, escrow, token_id);

    let logic = logic_utils::deploy_logic(&mut env, 1);

    let caller = env.create_light_account();
    env.call_private(caller, TestLogic::at(logic).withdraw_nft(escrow, recipient, nft, token_id));
}
