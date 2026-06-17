//! Lean PoC suite for labeled (non-fungible) private balances.
//!
//! A private origin label is `H(seed)`, where the contract draws `seed` from `random()`. Minting
//! (or re-entry) nullifies the seed, so fresh private origins should create distinct labels. Tests
//! learn the generated label from the plaintext private disclosure log emitted by the contract.
//!
//! Run: `yarn test:labels-poc` (uses `aztec test`, not bare `nargo test`).
use crate::{
    test::{
        capsule_labels::{clear_spend_labels, push_spend_label, set_query_label},
        utils::{self, mint_amount},
    },
    Token,
};
use aztec::{
    protocol::address::AztecAddress,
    test::helpers::{test_environment::{CallPrivateOptions, TestEnvironment}, txe_oracles},
};

global LABEL_CREATED: Field = 1;
global LABEL_DESHIELD: Field = 2;
global LABEL_BURN: Field = 3;

unconstrained fn balance_under_label(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    owner: AztecAddress,
    label: Field,
) -> u128 {
    set_query_label(env, token_contract_address, owner, label);
    env.execute_utility(Token::at(token_contract_address).balance_of_private(owner))
}

unconstrained fn label_disclosure_at(kind: Field, occurrence: u32) -> (Field, u128) {
    let effects = txe_oracles::get_last_tx_effects();
    let mut seen = 0;
    let mut found = false;
    let mut label = 0;
    let mut amount = 0 as u128;

    for i in 0..effects.private_logs.len() {
        let log = effects.private_logs.get(i);

        // The label disclosure log payload is [tag, label, amount, kind]. Other private logs
        // emitted by note delivery have different lengths and are ignored here.
        if log.len() == 4 {
            if log.get(3) == kind {
                if seen == occurrence {
                    found = true;
                    label = log.get(1);
                    amount = log.get(2) as u128;
                }
                seen += 1;
            }
        }
    }

    assert(found, "missing label disclosure");
    (label, amount)
}

unconstrained fn last_label_disclosure(kind: Field) -> (Field, u128) {
    label_disclosure_at(kind, 0)
}

unconstrained fn mint_labeled(
    env: TestEnvironment,
    token: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
    minter: AztecAddress,
) -> Field {
    env.call_private_opts(
        minter,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).mint_to_private(recipient, amount),
    );

    let (label, logged_amount) = last_label_disclosure(LABEL_CREATED);
    assert(logged_amount == amount, "created label amount log wrong");
    label
}

#[test]
unconstrained fn poc_mint_creates_label() {
    let (env, token, account, _, minter) = utils::setup_with_minter(false);

    let label = mint_labeled(env, token, account, mint_amount, minter);

    assert(
        balance_under_label(env, token, account, label) == mint_amount,
        "mint should land under disclosed label",
    );
}

#[test]
unconstrained fn poc_random_mint_labels_are_distinct() {
    let (env, token, account, _, minter) = utils::setup_with_minter(false);

    let first_label = mint_labeled(env, token, account, mint_amount, minter);
    let second_label = mint_labeled(env, token, account, mint_amount, minter);

    assert(first_label != second_label, "random mint labels should differ");
    assert(
        balance_under_label(env, token, account, first_label) == mint_amount,
        "first label balance wrong",
    );
    assert(
        balance_under_label(env, token, account, second_label) == mint_amount,
        "second label balance wrong",
    );
}

#[test]
unconstrained fn poc_reentry_creates_fresh_label() {
    let (env, token, owner, recipient, minter) = utils::setup_with_minter(false);

    // Give `owner` public funds, then shield them (public -> private).
    env.call_public(minter, Token::at(token).mint_to_public(owner, mint_amount));
    env.call_private_opts(
        owner,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).transfer_public_to_private(owner, recipient, mint_amount, 0),
    );

    let (label, logged_amount) = last_label_disclosure(LABEL_CREATED);
    assert(logged_amount == mint_amount, "re-entry label amount log wrong");

    // Re-entry mints a fresh private origin label -- a per-event id, not a function of `from`.
    assert(
        balance_under_label(env, token, recipient, label) == mint_amount,
        "re-entry should land under a fresh disclosed label",
    );
}

#[test]
unconstrained fn poc_burn_drains_and_discloses() {
    let (env, token, owner, _, minter) = utils::setup_with_minter(false);

    let label_a = mint_labeled(env, token, owner, mint_amount, minter);

    let burn_amount = mint_amount / 2;
    push_spend_label(env, token, owner, label_a);

    // Burn emits a plaintext private label log (kind=LABEL_BURN); the burned origin is drained
    // from the owner's bucket.
    env.call_private_opts(
        owner,
        CallPrivateOptions::new(),
        Token::at(token).burn_private(owner, burn_amount, 0),
    );

    let (retired_label, retired_amount) = last_label_disclosure(LABEL_BURN);
    assert(retired_label == label_a, "burn label log wrong");
    assert(retired_amount == burn_amount, "burn amount log wrong");

    assert(
        balance_under_label(env, token, owner, label_a) == mint_amount - burn_amount,
        "remaining labeled balance after burn wrong",
    );
}

#[test]
unconstrained fn poc_labeled_mints_are_isolated() {
    let (env, token, account, _, minter) = utils::setup_with_minter(false);

    let half = mint_amount / 2;

    let label_a = mint_labeled(env, token, account, half, minter);
    let label_b = mint_labeled(env, token, account, half, minter);

    assert(balance_under_label(env, token, account, label_a) == half, "label A balance wrong");
    assert(balance_under_label(env, token, account, label_b) == half, "label B balance wrong");
}

#[test]
unconstrained fn poc_spend_single_label_bucket() {
    let (env, token, owner, recipient, minter) = utils::setup_with_minter(false);

    let label_a = mint_labeled(env, token, owner, mint_amount, minter);

    let transfer_amount = mint_amount / 2;
    push_spend_label(env, token, owner, label_a);

    // De-shielding emits a plaintext private label log for the spent label.
    env.call_private_opts(
        owner,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).transfer_private_to_public(owner, recipient, transfer_amount, 0),
    );

    let (retired_label, retired_amount) = last_label_disclosure(LABEL_DESHIELD);
    assert(retired_label == label_a, "de-shield label log wrong");
    assert(retired_amount == transfer_amount, "de-shield amount log wrong");

    assert(
        balance_under_label(env, token, owner, label_a) == mint_amount - transfer_amount,
        "remaining labeled balance wrong",
    );
}

#[test]
unconstrained fn poc_private_transfer_preserves_labels() {
    let (env, token, owner, recipient, minter) = utils::setup_with_minter(false);

    let half = mint_amount / 2;
    let quarter = mint_amount / 4;

    let label_a = mint_labeled(env, token, owner, half, minter);
    let label_b = mint_labeled(env, token, owner, half, minter);

    // Spend all of A and half of B, in queue order.
    clear_spend_labels(env, token, owner);
    push_spend_label(env, token, owner, label_a);
    push_spend_label(env, token, owner, label_b);

    let spend_amount = half + quarter;
    env.call_private_opts(
        owner,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).transfer_private_to_private(owner, recipient, spend_amount, 0),
    );

    // The recipient inherits the SOURCE labels, split by how much was drawn from each. Only the
    // minter could have created these labels, so the recipient cannot relabel incoming funds.
    assert(
        balance_under_label(env, token, recipient, label_a) == half,
        "recipient should inherit all of label A",
    );
    assert(
        balance_under_label(env, token, recipient, label_b) == quarter,
        "recipient should inherit the spent portion of label B",
    );

    // The sender keeps the unspent B change under B and nothing under the drained A.
    assert(
        balance_under_label(env, token, owner, label_a) == 0 as u128,
        "sender A should be drained",
    );
    assert(
        balance_under_label(env, token, owner, label_b) == quarter,
        "sender should keep the B change under B",
    );
}

#[test]
unconstrained fn poc_commitment_preserves_label() {
    let (env, token, owner, recipient, minter) = utils::setup_with_minter(false);

    let label_a = mint_labeled(env, token, owner, mint_amount, minter);

    // Recipient's commitment, completable by `owner`.
    let commitment = env.call_private_opts(
        owner,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).initialize_transfer_commitment(recipient, owner),
    );

    // Owner funds the commitment from label A; it must complete into that same label.
    push_spend_label(env, token, owner, label_a);
    env.call_private_opts(
        owner,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).transfer_private_to_commitment(owner, commitment, mint_amount, 0),
    );

    // The recipient received the funds under the SAME origin label (preserved through the commitment).
    assert(
        balance_under_label(env, token, recipient, label_a) == mint_amount,
        "commitment should preserve label A",
    );
    assert(balance_under_label(env, token, owner, label_a) == 0 as u128, "owner label A drained");
}

#[test]
unconstrained fn poc_spend_across_two_labels_in_queue() {
    let (env, token, owner, recipient, minter) = utils::setup_with_minter(false);

    let half = mint_amount / 2;

    let label_a = mint_labeled(env, token, owner, half, minter);
    let label_b = mint_labeled(env, token, owner, half, minter);

    clear_spend_labels(env, token, owner);
    push_spend_label(env, token, owner, label_a);
    push_spend_label(env, token, owner, label_b);

    let spend_amount = (half + half) - 1;
    // De-shielding emits a plaintext private label log for each spent label.
    env.call_private_opts(
        owner,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).transfer_private_to_public(owner, recipient, spend_amount, 0),
    );

    let (retired_label_a, retired_amount_a) = label_disclosure_at(LABEL_DESHIELD, 0);
    let (retired_label_b, retired_amount_b) = label_disclosure_at(LABEL_DESHIELD, 1);
    assert(retired_label_a == label_a, "first de-shield label log wrong");
    assert(retired_amount_a == half, "first de-shield amount log wrong");
    assert(retired_label_b == label_b, "second de-shield label log wrong");
    assert(retired_amount_b == half - 1, "second de-shield amount log wrong");

    assert(
        balance_under_label(env, token, owner, label_a) == 0 as u128,
        "label A should be drained",
    );
    assert(
        balance_under_label(env, token, owner, label_b) == 1 as u128,
        "label B should hold change",
    );
}
