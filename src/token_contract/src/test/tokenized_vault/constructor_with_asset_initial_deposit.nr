use crate::{
    test::utils::{
        authorize_transfer_public_to_public, check_public_balance, check_total_supply,
        get_public_balance, get_total_supply, setup_with_asset_initial_deposit, setup_with_minter,
    },
    Token,
};
use aztec::protocol::address::AztecAddress;

// TODO: When salt setting in env deployment is supported we can precompute the vault address and
// compute the authwit before deployment. Deployment use constructor_with_asset for now.

#[test]
unconstrained fn vault_with_initial_deposit_success() {
    let initial_deposit: u128 = 1000;

    // 1. Setup environment with asset token and minter
    let (mut env, asset_address, owner, _, minter) = setup_with_minter(true);

    // 2. Mint initial_deposit assets to owner
    env.call_public(minter, Token::at(asset_address).mint_to_public(owner, initial_deposit));

    // 3. Deploy vault with constructor_with_asset (no initial deposit in constructor)
    let vault_initializer = Token::interface().constructor_with_asset(
        "Vault00000000000000000000000000",
        "VAULT00000000000000000000000000",
        18,
        asset_address,
        1,
        AztecAddress::zero(),
    );
    let vault_address =
        env.deploy("@token_contract/Token").with_public_initializer(owner, vault_initializer);

    // 4. Authorize vault to transfer assets from owner
    authorize_transfer_public_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        initial_deposit,
        0,
    );

    // 5. Deposit to vault with shares going to vault address itself (locked shares)
    env.call_public(
        owner,
        Token::at(vault_address).deposit_public_to_public(owner, vault_address, initial_deposit, 0),
    );

    // Verify owner's asset balance is now 0 (initial deposit was transferred to vault)
    check_public_balance(env, asset_address, owner, 0);

    // Verify vault holds the initial deposit assets
    check_public_balance(env, asset_address, vault_address, initial_deposit);

    // Verify shares are locked in the vault contract itself (not owner)
    check_public_balance(env, vault_address, vault_address, initial_deposit);

    // Verify owner has no shares
    check_public_balance(env, vault_address, owner, 0);

    // Verify total supply equals the locked shares
    check_total_supply(env, vault_address, initial_deposit);
}

#[test]
unconstrained fn vault_with_initial_deposit_subsequent_deposits_work() {
    let initial_deposit: u128 = 1000;
    let (env, vault_address, owner, recipient, asset_address, minter) =
        setup_with_asset_initial_deposit(false, initial_deposit);

    // Mint more assets to owner
    let second_deposit: u128 = 500;
    env.call_public(minter, Token::at(asset_address).mint_to_public(owner, second_deposit));

    // Authorize and deposit
    authorize_transfer_public_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        second_deposit,
        0,
    );

    env.call_public(
        owner,
        Token::at(vault_address).deposit_public_to_public(owner, recipient, second_deposit, 0),
    );

    // Verify recipient got shares (1:1 ratio since initial deposit established the rate)
    let recipient_shares = get_public_balance(env, vault_address, recipient);
    assert(recipient_shares == second_deposit, "Recipient should receive proportional shares");

    // Vault's locked shares remain unchanged
    let locked_shares = get_public_balance(env, vault_address, vault_address);
    assert(locked_shares == initial_deposit, "Locked shares should remain unchanged");

    // Verify total supply = initial locked shares + recipient's shares
    let total_supply = get_total_supply(env, vault_address);
    assert(total_supply == initial_deposit + second_deposit, "Total supply should be updated");
}

#[test]
unconstrained fn vault_with_initial_deposit_yield_distribution() {
    let initial_deposit: u128 = 1000;
    let (env, vault_address, owner, recipient, asset_address, minter) =
        setup_with_asset_initial_deposit(false, initial_deposit);

    // Recipient deposits same amount as initial deposit
    let deposit_amount: u128 = 1000;
    env.call_public(minter, Token::at(asset_address).mint_to_public(owner, deposit_amount));

    authorize_transfer_public_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
        0,
    );

    env.call_public(
        owner,
        Token::at(vault_address).deposit_public_to_public(owner, recipient, deposit_amount, 0),
    );

    // Simulate yield by minting assets directly to the vault
    let yield_amount: u128 = 200;
    env.call_public(minter, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // Now recipient redeems their shares
    env.call_public(
        recipient,
        Token::at(vault_address).redeem_public_to_public(recipient, recipient, deposit_amount, 0),
    );

    // Recipient should have received more than deposit_amount due to yield
    // Total shares = initial_deposit + deposit_amount = 2000
    // Total assets = initial_deposit + deposit_amount + yield = 2200
    // Recipient's share = 1000/2000 * 2200 = 1100
    let recipient_assets = get_public_balance(env, asset_address, recipient);
    assert(
        recipient_assets > deposit_amount,
        "Recipient should have received more assets due to yield",
    );

    // Locked shares remain unchanged
    let locked_shares = get_public_balance(env, vault_address, vault_address);
    assert(locked_shares == initial_deposit, "Locked shares should remain unchanged");
}
