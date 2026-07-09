use crate::MultiToken;
use crate::test::utils::{self, mint_amount};

#[test]
unconstrained fn mint_to_public_success() {
    // Minter mints (id, amount) to public; recipient's public balance of id equals amount.
    let (env, multitoken_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let id: Field = 1;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, mint_amount),
    );

    utils::check_public_balance(env, multitoken_contract_address, owner, id, mint_amount);
}

#[test(should_fail_with = "caller is not minter")]
unconstrained fn mint_to_public_failure_as_non_minter() {
    // A non-minter calling mint_to_public must revert.
    let (env, multitoken_contract_address, owner, recipient, _) = utils::setup_with_minter(false);

    let id: Field = 1;
    let mint_to_public_call_interface =
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, mint_amount);
    // As non-minter
    env.call_public(recipient, mint_to_public_call_interface);
}

// Overflow expression derived from MultiToken main.nr:555 (`_increase_public_balance`). MultiToken keys the public
// balance by (id, owner), so the compiler-embedded expression is `at(id).at(owner)`, NOT the token's `at(to)`.
#[test(should_fail_with = "attempt to add with overflow 'self.storage.public_balances.at(id).at(owner).read() + amount'")]
unconstrained fn mint_to_public_failure_balance_overflow() {
    // Mint max_u128 of id then +1 to overflow the public balance.
    let (env, multitoken_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let id: Field = 1;
    let max = utils::max_u128();
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, max),
    );

    // Overflow the recipient's public balance of id
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id, 1 as u128),
    );
}

#[test]
unconstrained fn mint_to_public_per_id_isolation() {
    // Public balances are keyed by (id, owner), so minting (idX, a),(idY, b) keeps each independent.
    let (env, multitoken_contract_address, owner, _, minter) = utils::setup_with_minter(false);

    let id_x: Field = 1;
    let id_y: Field = 2;
    let amount_x: u128 = 7_000;
    let amount_y: u128 = 3_000;

    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id_x, amount_x),
    );
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id_y, amount_y),
    );

    utils::check_public_balance(env, multitoken_contract_address, owner, id_x, amount_x);
    utils::check_public_balance(env, multitoken_contract_address, owner, id_y, amount_y);
}
