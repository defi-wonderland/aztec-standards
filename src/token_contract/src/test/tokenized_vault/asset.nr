use crate::{test::utils, Token};

#[test]
unconstrained fn asset_returns_correct_address() {
    // Setup with asset token
    let (env, vault_address, _owner, _recipient, asset_address) = utils::setup_with_asset(false);

    // Get the asset address from the vault
    let returned_asset = env.view_public(Token::at(vault_address).asset());

    // Assert the returned asset address matches the deployed asset
    assert(returned_asset == asset_address, "asset() should return the correct asset address");
}
