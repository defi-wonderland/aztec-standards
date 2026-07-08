use crate::MultiToken;
use crate::test::utils;

#[test]
unconstrained fn balance_of_public_default_zero() {
    // A fresh deploy has zero public balance for any (owner, id).
    let (env, multitoken_contract_address, owner, _, _) = utils::setup_with_minter(false);

    let id: Field = 1;
    let balance =
        env.view_public(MultiToken::at(multitoken_contract_address).balance_of_public(owner, id));
    assert(balance == 0 as u128, "default public balance should be zero");
}

#[test]
unconstrained fn balance_of_private_default_zero() {
    // A fresh deploy has zero private balance for any (owner, id).
    let (env, multitoken_contract_address, owner, _, _) = utils::setup_with_minter(false);

    let id: Field = 1;
    let balance = env.execute_utility(MultiToken::at(multitoken_contract_address)
        .balance_of_private(owner, id));
    assert(balance == 0 as u128, "default private balance should be zero");
}

#[test]
unconstrained fn balance_of_private_sums_same_id_notes_only() {
    // Several notes of idX plus one of idY: balance_of_private(owner, idX) sums only idX notes
    // (off-chain select(token_id == idX)).
    let (env, multitoken_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let id_x: Field = 1;
    let id_y: Field = 2;
    let note_1: u128 = 1_000;
    let note_2: u128 = 2_000;
    let note_3: u128 = 3_000;
    let note_y: u128 = 9_999;

    utils::mint_to_private(
        env,
        multitoken_contract_address,
        owner,
        id_x,
        note_1,
        minter,
    );
    utils::mint_to_private(
        env,
        multitoken_contract_address,
        owner,
        id_x,
        note_2,
        minter,
    );
    utils::mint_to_private(
        env,
        multitoken_contract_address,
        owner,
        id_x,
        note_3,
        minter,
    );
    utils::mint_to_private(
        env,
        multitoken_contract_address,
        owner,
        id_y,
        note_y,
        minter,
    );

    utils::check_private_balance(
        env,
        multitoken_contract_address,
        owner,
        id_x,
        note_1 + note_2 + note_3,
    );
    // idY notes are excluded from the idX sum.
    utils::check_private_balance(env, multitoken_contract_address, owner, id_y, note_y);
}
