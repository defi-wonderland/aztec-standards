use crate::MultiToken;
use crate::test::utils::{self, mint_amount};

#[test]
unconstrained fn mint_to_private_success() {
    // Minter mints (id, amount); recipient's private balance of id equals amount.
    let (env, multitoken_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let id: Field = 1;
    env.call_private(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_private(owner, id, mint_amount),
    );

    utils::check_private_balance(env, multitoken_contract_address, owner, id, mint_amount);
}

#[test]
unconstrained fn mint_to_private_id_zero_success() {
    // id = 0 is legal: this is a positive case, not a rejection.
    let (env, multitoken_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let id: Field = 0;
    env.call_private(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_private(owner, id, mint_amount),
    );

    utils::check_private_balance(env, multitoken_contract_address, owner, id, mint_amount);
}

#[test(should_fail_with = "caller is not minter")]
unconstrained fn mint_to_private_failure_as_non_minter() {
    // A non-minter calling mint_to_private must revert.
    let (env, multitoken_contract_address, owner, recipient, _) = utils::setup_with_minter(false);

    let id: Field = 1;
    let mint_to_private_call_interface =
        MultiToken::at(multitoken_contract_address).mint_to_private(owner, id, mint_amount);
    // As non-minter (recipient is not the minter)
    env.call_private(recipient, mint_to_private_call_interface);
}

#[test]
unconstrained fn mint_to_private_per_id_isolation() {
    // Minting (idX, a) then (idY, b) leaves each id's balance independent.
    let (env, multitoken_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let id_x: Field = 1;
    let id_y: Field = 2;
    let amount_x: u128 = 7_000;
    let amount_y: u128 = 3_000;

    env.call_private(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_private(owner, id_x, amount_x),
    );
    utils::mint_to_private(
        env,
        multitoken_contract_address,
        owner,
        id_y,
        amount_y,
        minter,
    );

    utils::check_private_balance(env, multitoken_contract_address, owner, id_x, amount_x);
    utils::check_private_balance(env, multitoken_contract_address, owner, id_y, amount_y);
}

#[test]
unconstrained fn mint_to_private_no_public_side_effect() {
    // A fully-private mint has no public effect: the public balance of id stays 0.
    let (env, multitoken_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let id: Field = 1;
    env.call_private(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_private(owner, id, mint_amount),
    );

    utils::check_private_balance(env, multitoken_contract_address, owner, id, mint_amount);
    utils::check_public_balance(env, multitoken_contract_address, owner, id, 0 as u128);
}
