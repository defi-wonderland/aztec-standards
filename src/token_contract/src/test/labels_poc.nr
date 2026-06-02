//! Lean PoC suite for labeled (non-fungible) private balances via PXE capsules.
//!
//! Run: `yarn test:labels-poc` (uses `aztec test`, not bare `nargo test`).
use crate::{
    test::{
        capsule_labels::{
            clear_spend_labels, NULL_LABEL, push_spend_label, set_query_label, set_receive_label,
        },
        utils::{self, mint_amount},
    },
    Token,
};
use aztec::{
    protocol::address::AztecAddress,
    test::helpers::test_environment::{CallPrivateOptions, TestEnvironment},
};

global LABEL_A: Field = 0xA;
global LABEL_B: Field = 0xB;

unconstrained fn balance_under_label(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    owner: AztecAddress,
    label: Field,
) -> u128 {
    set_query_label(env, token_contract_address, owner, label);
    env.execute_utility(Token::at(token_contract_address).balance_of_private(owner))
}

unconstrained fn mint_labeled(
    env: TestEnvironment,
    token: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
    minter: AztecAddress,
    label: Field,
) {
    set_receive_label(env, token, recipient, label);
    env.call_private_opts(
        minter,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).mint_to_private(recipient, amount),
    );
}

#[test]
unconstrained fn poc_default_null_label_roundtrip() {
    let (env, token, _, _, minter) = utils::setup_with_minter(false);

    // No receive-label capsule: contract credits NULL_LABEL; minter mints to self (single scope).
    utils::mint_to_private(env, token, minter, mint_amount, minter);

    let balance = balance_under_label(env, token, minter, NULL_LABEL);
    assert(balance == mint_amount, "NULL_LABEL balance should match mint");
}

#[test]
unconstrained fn poc_labeled_mints_are_isolated() {
    let (env, token, account, _, minter) = utils::setup_with_minter(false);

    let half = mint_amount / 2;

    mint_labeled(env, token, account, half, minter, LABEL_A);
    mint_labeled(env, token, account, half, minter, LABEL_B);

    assert(balance_under_label(env, token, account, LABEL_A) == half, "label A balance wrong");
    assert(balance_under_label(env, token, account, LABEL_B) == half, "label B balance wrong");
    assert(
        balance_under_label(env, token, account, NULL_LABEL) == 0 as u128,
        "unlabeled bucket should be empty",
    );
}

#[test]
unconstrained fn poc_spend_single_label_bucket() {
    let (env, token, owner, recipient, minter) = utils::setup_with_minter(false);

    mint_labeled(env, token, owner, mint_amount, minter, LABEL_A);

    let transfer_amount = mint_amount / 2;
    push_spend_label(env, token, owner, LABEL_A);

    env.call_private_opts(
        owner,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).transfer_private_to_public(owner, recipient, transfer_amount, 0),
    );

    assert(
        balance_under_label(env, token, owner, LABEL_A) == mint_amount - transfer_amount,
        "remaining labeled balance wrong",
    );
}

#[test]
unconstrained fn poc_spend_across_two_labels_in_queue() {
    let (env, token, owner, recipient, minter) = utils::setup_with_minter(false);

    let half = mint_amount / 2;

    mint_labeled(env, token, owner, half, minter, LABEL_A);
    mint_labeled(env, token, owner, half, minter, LABEL_B);

    clear_spend_labels(env, token, owner);
    push_spend_label(env, token, owner, LABEL_A);
    push_spend_label(env, token, owner, LABEL_B);

    let spend_amount = (half + half) - 1;
    env.call_private_opts(
        owner,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).transfer_private_to_public(owner, recipient, spend_amount, 0),
    );

    assert(
        balance_under_label(env, token, owner, LABEL_A) == 0 as u128,
        "label A should be drained",
    );
    assert(
        balance_under_label(env, token, owner, LABEL_B) == 1 as u128,
        "label B should hold change",
    );
}
