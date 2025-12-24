use crate::{test::utils, Token};

/// NOTE: `max_deposit` returns the maximum amount of assets that can be deposited.
/// Since there are no deposit limits in this implementation, it always returns MAX_U128_VALUE.
/// The receiver parameter is included for ERC4626 compatibility but is unused.

// Maximum value for a u128 (2**128 - 1)
global MAX_U128_VALUE: u128 = 340282366920938463463374607431768211455;

#[test]
unconstrained fn max_deposit_returns_max_value() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, _asset_address) = utils::setup_with_asset(false);

    // max_deposit should return MAX_U128_VALUE for any address
    let max_deposit = env.view_public(Token::at(vault_address).max_deposit(owner));

    assert(max_deposit == MAX_U128_VALUE, "max_deposit should return MAX_U128_VALUE");
}

#[test]
unconstrained fn max_deposit_same_for_any_address() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, _asset_address) = utils::setup_with_asset(false);

    // max_deposit should return the same value regardless of address
    let max_deposit_owner = env.view_public(Token::at(vault_address).max_deposit(owner));
    let max_deposit_recipient = env.view_public(Token::at(vault_address).max_deposit(recipient));

    assert(
        max_deposit_owner == max_deposit_recipient,
        "max_deposit should be same for all addresses",
    );
    assert(max_deposit_owner == MAX_U128_VALUE, "max_deposit should return MAX_U128_VALUE");
}
