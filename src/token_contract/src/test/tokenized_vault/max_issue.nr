use crate::{test::utils, Token};

/// NOTE: `max_issue` returns the maximum amount of shares that can be issued.
/// Since there are no issuance limits in this implementation, it always returns MAX_U128_VALUE.
/// The receiver parameter is included for ERC4626 compatibility but is unused.

// Maximum value for a u128 (2**128 - 1)
global MAX_U128_VALUE: u128 = 340282366920938463463374607431768211455;

#[test]
unconstrained fn max_issue_returns_max_value() {
    // Setup with asset token
    let (env, vault_address, owner, _recipient, _asset_address) = utils::setup_with_asset(false);

    // max_issue should return MAX_U128_VALUE for any address
    let max_issue = env.view_public(Token::at(vault_address).max_issue(owner));

    assert(max_issue == MAX_U128_VALUE, "max_issue should return MAX_U128_VALUE");
}

#[test]
unconstrained fn max_issue_same_for_any_address() {
    // Setup with asset token
    let (env, vault_address, owner, recipient, _asset_address) = utils::setup_with_asset(false);

    // max_issue should return the same value regardless of address
    let max_issue_owner = env.view_public(Token::at(vault_address).max_issue(owner));
    let max_issue_recipient = env.view_public(Token::at(vault_address).max_issue(recipient));

    assert(max_issue_owner == max_issue_recipient, "max_issue should be same for all addresses");
    assert(max_issue_owner == MAX_U128_VALUE, "max_issue should return MAX_U128_VALUE");
}
