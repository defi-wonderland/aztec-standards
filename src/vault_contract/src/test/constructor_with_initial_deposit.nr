use crate::{
    test::utils::{
        authorize_transfer_public_to_public, check_public_balance, get_public_balance,
        redeem_public_to_public, setup_with_vault_initial_deposit,
    },
    Vault,
};
use token_contract::test::utils::{check_total_supply, get_total_supply};
use token_contract::Token;

// TODO: TXE does not support custom salts, so the vault's computed shares address won't match
// the deployed shares token. Tests will fail until custom salt support is added to TXE.
// See: https://github.com/AztecProtocol/aztec-packages/issues/16656

#[test]
unconstrained fn vault_with_initial_deposit_success() {
    let initial_deposit: u128 = 1000;

    // Setup environment with vault and initial deposit
    let (env, vault_address, owner, _recipient, asset_address, shares_address) =
        setup_with_vault_initial_deposit(false, initial_deposit);

    // Verify owner's asset balance is now 0 (initial deposit was transferred to vault)
    check_public_balance(env, asset_address, owner, 0);

    // Verify vault holds the initial deposit assets
    check_public_balance(env, asset_address, vault_address, initial_deposit);

    // Verify shares are locked in the vault contract itself (not owner)
    check_public_balance(env, shares_address, vault_address, initial_deposit);

    // Verify owner has no shares
    check_public_balance(env, shares_address, owner, 0);

    // Verify total supply equals the locked shares
    check_total_supply(env, shares_address, initial_deposit);
}

#[test]
unconstrained fn vault_with_initial_deposit_subsequent_deposits_work() {
    let initial_deposit: u128 = 1000;
    let (env, vault_address, owner, recipient, asset_address, shares_address) =
        setup_with_vault_initial_deposit(false, initial_deposit);

    // Mint more assets to owner
    let second_deposit: u128 = 500;
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, second_deposit));

    // Authorize and deposit
    authorize_transfer_public_to_public(env, asset_address, vault_address, owner, second_deposit);

    env.call_public(
        owner,
        Vault::at(vault_address).deposit_public_to_public(owner, recipient, second_deposit, 0),
    );

    // Verify recipient got shares (1:1 ratio since initial deposit established the rate)
    let recipient_shares = get_public_balance(env, shares_address, recipient);
    assert(recipient_shares == second_deposit, "Recipient should receive proportional shares");

    // Vault's locked shares remain unchanged
    let locked_shares = get_public_balance(env, shares_address, vault_address);
    assert(locked_shares == initial_deposit, "Locked shares should remain unchanged");

    // Verify total supply = initial locked shares + recipient's shares
    let total_supply = get_total_supply(env, shares_address);
    assert(total_supply == initial_deposit + second_deposit, "Total supply should be updated");
}

#[test]
unconstrained fn vault_with_initial_deposit_yield_distribution() {
    let initial_deposit: u128 = 1000;
    let (env, vault_address, owner, recipient, asset_address, shares_address) =
        setup_with_vault_initial_deposit(false, initial_deposit);

    // Recipient deposits same amount as initial deposit
    let deposit_amount: u128 = 1000;
    env.call_public(owner, Token::at(asset_address).mint_to_public(owner, deposit_amount));

    authorize_transfer_public_to_public(env, asset_address, vault_address, owner, deposit_amount);

    env.call_public(
        owner,
        Vault::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0),
    );

    // Simulate yield by minting assets directly to the vault
    let yield_amount: u128 = 200;
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // Recipient redeems their shares
    redeem_public_to_public(
        env,
        vault_address,
        shares_address,
        recipient,
        recipient,
        deposit_amount,
    );

    // Recipient should have received more than deposit_amount due to yield
    // Total shares = initial_deposit + deposit_amount = 2000
    // Total assets = initial_deposit + deposit_amount + yield = 2200
    // Recipient's share = 1000 * (2200 + 1) / (2000 + 1) = 1099 (virtual offset rounding)
    let recipient_assets = get_public_balance(env, asset_address, recipient);
    let expected_assets: u128 = 1099;
    assert(recipient_assets == expected_assets, "Recipient should receive exactly 1099 assets");

    // Locked shares remain unchanged
    let locked_shares = get_public_balance(env, shares_address, vault_address);
    assert(locked_shares == initial_deposit, "Locked shares should remain unchanged");
}
