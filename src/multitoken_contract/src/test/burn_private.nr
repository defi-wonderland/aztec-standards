use crate::MultiToken;
use crate::test::utils::{self, mint_amount};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

#[test]
unconstrained fn burn_private_on_behalf_of_self() {
    // Burn (id, amount); owner's private balance reduces; nothing is credited.
    let (env, multitoken_contract_address, owner, _, _) =
        utils::setup_and_mint_to_private_with_minter(false, 1);

    let id: Field = 1;
    let burn_amount = mint_amount / (10 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).burn_private(owner, id, burn_amount, 0),
    );

    utils::check_private_balance(
        env,
        multitoken_contract_address,
        owner,
        id,
        mint_amount - burn_amount,
    );
}

#[test]
unconstrained fn burn_private_on_behalf_of_other() {
    // burn_private is 4-arg (from, id, amount, _nonce) -> forward_private_4.
    let (env, multitoken_contract_address, owner, _, _, proxy) =
        utils::setup_and_mint_to_private_with_proxy(1);

    let id: Field = 1;
    let burn_amount = mint_amount / (10 as u128);
    let call_interface =
        MultiToken::at(multitoken_contract_address).burn_private(owner, id, burn_amount, 1);
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, proxy, call_interface);
    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_4(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );

    utils::check_private_balance(
        env,
        multitoken_contract_address,
        owner,
        id,
        mint_amount - burn_amount,
    );
}

#[test(should_fail_with = "Balance too low")]
unconstrained fn burn_private_failure_more_than_balance() {
    // Burning more than balance reverts "Balance too low".
    let (env, multitoken_contract_address, owner, _, _) =
        utils::setup_and_mint_to_private_with_minter(false, 1);

    let id: Field = 1;
    let burn_amount = mint_amount + (1 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).burn_private(owner, id, burn_amount, 0),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn burn_private_failure_on_behalf_of_other_without_approval() {
    // Proxy with NO authwit reverts on the missing private authwit.
    let (env, multitoken_contract_address, owner, _, _, proxy) =
        utils::setup_and_mint_to_private_with_proxy(1);

    let id: Field = 1;
    let burn_amount = mint_amount / (10 as u128);
    let call_interface =
        MultiToken::at(multitoken_contract_address).burn_private(owner, id, burn_amount, 1);
    // No authwit added.
    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_4(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn burn_private_failure_on_behalf_of_other_wrong_designated_caller() {
    // Authwit granted to `owner` (not the proxy) must still revert.
    let (env, multitoken_contract_address, owner, _, _, proxy) =
        utils::setup_and_mint_to_private_with_proxy(1);

    let id: Field = 1;
    let burn_amount = mint_amount / (10 as u128);
    let call_interface =
        MultiToken::at(multitoken_contract_address).burn_private(owner, id, burn_amount, 1);
    // Authwit added for the wrong caller (owner instead of proxy).
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, owner, call_interface);
    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_4(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );
}

#[test]
unconstrained fn burn_private_no_public_side_effect() {
    // A fully-private burn writes no public balance.
    let (env, multitoken_contract_address, owner, _, _) =
        utils::setup_and_mint_to_private_with_minter(false, 1);

    let id: Field = 1;
    let burn_amount = mint_amount / (10 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).burn_private(owner, id, burn_amount, 0),
    );

    utils::check_public_balance(env, multitoken_contract_address, owner, id, 0 as u128);
}
