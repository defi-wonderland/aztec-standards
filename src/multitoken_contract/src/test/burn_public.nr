use crate::MultiToken;
use crate::test::utils::{self, mint_amount};
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test]
unconstrained fn burn_public_success() {
    // Burn (id, amount); owner's public balance reduces. There is no total_supply.
    let (env, multitoken_contract_address, owner, _, _) =
        utils::setup_and_mint_to_public_with_minter(false, 1);

    let id: Field = 1;
    let burn_amount = mint_amount / (10 as u128);
    env.call_public(
        owner,
        MultiToken::at(multitoken_contract_address).burn_public(owner, id, burn_amount, 0),
    );

    utils::check_public_balance(
        env,
        multitoken_contract_address,
        owner,
        id,
        mint_amount - burn_amount,
    );
}

#[test]
unconstrained fn burn_public_on_behalf_of_other() {
    // Public authwit uses a second account as caller (no proxy needed for public).
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(true, 1);

    let id: Field = 1;
    let burn_amount = mint_amount / (10 as u128);
    let call_interface =
        MultiToken::at(multitoken_contract_address).burn_public(owner, id, burn_amount, 1);
    authwit_cheatcodes::add_public_authwit_from_call(env, owner, recipient, call_interface);
    env.call_public(recipient, call_interface);

    utils::check_public_balance(
        env,
        multitoken_contract_address,
        owner,
        id,
        mint_amount - burn_amount,
    );
}

// Public underflow expression from MultiToken main.nr:565 (`_decrease_public_balance`); keyed (id, owner).
#[test(should_fail_with = "attempt to subtract with overflow 'self.storage.public_balances.at(id).at(owner).read() - amount'")]
unconstrained fn burn_public_failure_more_than_balance() {
    // Burning more than balance underflows the public balance.
    let (env, multitoken_contract_address, owner, _, _) =
        utils::setup_and_mint_to_public_with_minter(false, 1);

    let id: Field = 1;
    let burn_amount = mint_amount * (10 as u128);
    env.call_public(
        owner,
        MultiToken::at(multitoken_contract_address).burn_public(owner, id, burn_amount, 0),
    );
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn burn_public_failure_on_behalf_of_other_without_approval() {
    // caller != from with NO authwit is rejected by the public authwit check.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(true, 1);

    let id: Field = 1;
    let burn_amount = mint_amount / (10 as u128);
    let call_interface =
        MultiToken::at(multitoken_contract_address).burn_public(owner, id, burn_amount, 1);
    // No authwit added.
    env.call_public(recipient, call_interface);
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn burn_public_failure_on_behalf_of_other_wrong_caller() {
    // Authwit granted to `owner` (not the actual caller `recipient`) must still be rejected.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(true, 1);

    let id: Field = 1;
    let burn_amount = mint_amount / (10 as u128);
    let call_interface =
        MultiToken::at(multitoken_contract_address).burn_public(owner, id, burn_amount, 1);
    authwit_cheatcodes::add_public_authwit_from_call(env, owner, owner, call_interface);
    env.call_public(recipient, call_interface);
}
