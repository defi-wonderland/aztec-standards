//! Lean PoC suite for labeled (non-fungible) private balances.
//!
//! A private origin label is `H(seed)`, where the contract draws `seed` from `random()`. Minting
//! (or re-entry) nullifies the seed, so the same label can never be created twice. Tests pin the
//! seed by mocking the `aztec_utl_getRandomField` oracle, then assert against `origin_label(seed)`.
//!
//! Run: `yarn test:labels-poc` (uses `aztec test`, not bare `nargo test`).
use crate::{
    test::{
        capsule_labels::{clear_spend_labels, origin_label, push_spend_label, set_query_label},
        utils::{self, mint_amount},
    },
    Token,
};
use aztec::{
    protocol::address::AztecAddress,
    test::helpers::test_environment::{CallPrivateOptions, TestEnvironment},
};
use std::test::OracleMock;

global SEED_A: Field = 0xA;
global SEED_B: Field = 0xB;

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
    seed: Field,
) {
    // Pin the contract's random seed so the resulting label H(seed) is recomputable in the test.
    let _ = OracleMock::mock("aztec_utl_getRandomField").returns(seed);
    env.call_private_opts(
        minter,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).mint_to_private(recipient, amount),
    );
}

#[test]
unconstrained fn poc_mint_creates_label() {
    let (env, token, account, _, minter) = utils::setup_with_minter(false);

    mint_labeled(env, token, account, mint_amount, minter, SEED_A);

    let label_a = origin_label(SEED_A);
    assert(
        balance_under_label(env, token, account, label_a) == mint_amount,
        "mint should land under H(seed)",
    );
    // A different seed derives a different, empty bucket.
    assert(
        balance_under_label(env, token, account, origin_label(SEED_B)) == 0 as u128,
        "a different seed's bucket should be empty",
    );
}

#[test(should_fail)]
unconstrained fn poc_seed_is_single_use() {
    let (env, token, account, _, minter) = utils::setup_with_minter(false);

    // First mint of seed A succeeds and nullifies the seed.
    mint_labeled(env, token, account, mint_amount, minter, SEED_A);
    // Re-minting the same seed must revert: its nullifier already exists, so the same label can
    // never be minted again.
    mint_labeled(env, token, account, mint_amount, minter, SEED_A);
}

#[test]
unconstrained fn poc_reentry_creates_fresh_label() {
    let (env, token, owner, recipient, minter) = utils::setup_with_minter(false);

    // Give `owner` public funds, then shield them (public -> private).
    env.call_public(minter, Token::at(token).mint_to_public(owner, mint_amount));
    // Pin the fresh per-event seed the re-entry will use (random in production).
    let _ = OracleMock::mock("aztec_utl_getRandomField").returns(SEED_A);
    env.call_private_opts(
        owner,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).transfer_public_to_private(owner, recipient, mint_amount, 0),
    );

    // Re-entry mints a fresh private origin H(seed) -- a per-event id, not a function of `from`.
    assert(
        balance_under_label(env, token, recipient, origin_label(SEED_A)) == mint_amount,
        "re-entry should land under a fresh per-event H(seed) label",
    );
}

#[test]
unconstrained fn poc_burn_drains_and_discloses() {
    let (env, token, owner, _, minter) = utils::setup_with_minter(false);

    mint_labeled(env, token, owner, mint_amount, minter, SEED_A);
    let label_a = origin_label(SEED_A);

    let burn_amount = mint_amount / 2;
    push_spend_label(env, token, owner, label_a);

    // Burn emits a plaintext private label log (kind=LABEL_BURN); the burned origin is drained
    // from the owner's bucket.
    env.call_private_opts(
        owner,
        CallPrivateOptions::new(),
        Token::at(token).burn_private(owner, burn_amount, 0),
    );

    assert(
        balance_under_label(env, token, owner, label_a) == mint_amount - burn_amount,
        "remaining labeled balance after burn wrong",
    );
}

#[test]
unconstrained fn poc_labeled_mints_are_isolated() {
    let (env, token, account, _, minter) = utils::setup_with_minter(false);

    let half = mint_amount / 2;

    mint_labeled(env, token, account, half, minter, SEED_A);
    mint_labeled(env, token, account, half, minter, SEED_B);

    let label_a = origin_label(SEED_A);
    let label_b = origin_label(SEED_B);

    assert(balance_under_label(env, token, account, label_a) == half, "label A balance wrong");
    assert(balance_under_label(env, token, account, label_b) == half, "label B balance wrong");
}

#[test]
unconstrained fn poc_spend_single_label_bucket() {
    let (env, token, owner, recipient, minter) = utils::setup_with_minter(false);

    mint_labeled(env, token, owner, mint_amount, minter, SEED_A);
    let label_a = origin_label(SEED_A);

    let transfer_amount = mint_amount / 2;
    push_spend_label(env, token, owner, label_a);

    // De-shielding emits a plaintext private label log for the spent label.
    env.call_private_opts(
        owner,
        CallPrivateOptions::new().with_additional_scopes([recipient]),
        Token::at(token).transfer_private_to_public(owner, recipient, transfer_amount, 0),
    );

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

    mint_labeled(env, token, owner, half, minter, SEED_A);
    mint_labeled(env, token, owner, half, minter, SEED_B);

    let label_a = origin_label(SEED_A);
    let label_b = origin_label(SEED_B);

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

    mint_labeled(env, token, owner, mint_amount, minter, SEED_A);
    let label_a = origin_label(SEED_A);

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

    mint_labeled(env, token, owner, half, minter, SEED_A);
    mint_labeled(env, token, owner, half, minter, SEED_B);

    let label_a = origin_label(SEED_A);
    let label_b = origin_label(SEED_B);

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

    assert(
        balance_under_label(env, token, owner, label_a) == 0 as u128,
        "label A should be drained",
    );
    assert(
        balance_under_label(env, token, owner, label_b) == 1 as u128,
        "label B should hold change",
    );
}
