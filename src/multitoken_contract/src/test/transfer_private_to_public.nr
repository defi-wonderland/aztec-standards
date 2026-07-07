use crate::MultiToken;
use crate::test::utils::{self, mint_amount};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

#[test]
unconstrained fn transfer_private_to_public_success() {
    // Owner's private balance debits; recipient's PUBLIC balance credits the same amount.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_private_with_minter(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_public(
            owner,
            recipient,
            id,
            transfer_amount,
            0,
        ),
    );

    utils::check_private_balance(
        env,
        multitoken_contract_address,
        owner,
        id,
        mint_amount - transfer_amount,
    );
    utils::check_public_balance(
        env,
        multitoken_contract_address,
        recipient,
        id,
        transfer_amount,
    );
}

#[test]
unconstrained fn transfer_private_to_public_on_behalf_of_other() {
    // Proxy + private authwit + 5-arg forward.
    let (env, multitoken_contract_address, owner, recipient, _, proxy) =
        utils::setup_and_mint_to_private_with_proxy(1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_private_to_public(
        owner,
        recipient,
        id,
        transfer_amount,
        1,
    );
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, proxy, call_interface);
    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_5(
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
        mint_amount - transfer_amount,
    );
    utils::check_public_balance(
        env,
        multitoken_contract_address,
        recipient,
        id,
        transfer_amount,
    );
}

#[test(should_fail_with = "Balance too low")]
unconstrained fn transfer_private_to_public_failure_more_than_balance() {
    // Private debit exceeding balance reverts "Balance too low".
    let (env, multitoken_contract_address, owner, _, _) =
        utils::setup_and_mint_to_private_with_minter(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount + (1 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_public(
            owner,
            owner,
            id,
            transfer_amount,
            0,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn transfer_private_to_public_failure_on_behalf_of_other_without_approval() {
    // Proxy with NO authwit reverts on the missing private authwit.
    let (env, multitoken_contract_address, owner, recipient, _, proxy) =
        utils::setup_and_mint_to_private_with_proxy(1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_private_to_public(
        owner,
        recipient,
        id,
        transfer_amount,
        1,
    );
    // No authwit added.
    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_5(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );
}
