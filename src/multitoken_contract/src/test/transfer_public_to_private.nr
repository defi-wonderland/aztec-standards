use crate::MultiToken;
use crate::test::utils::{self, mint_amount};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

#[test]
unconstrained fn transfer_public_to_private_success() {
    // Owner's PUBLIC balance debits; recipient's PRIVATE balance credits the same amount.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (2 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_public_to_private(
            owner,
            recipient,
            id,
            transfer_amount,
            0,
        ),
    );

    utils::check_public_balance(
        env,
        multitoken_contract_address,
        owner,
        id,
        mint_amount - transfer_amount,
    );
    utils::check_private_balance(
        env,
        multitoken_contract_address,
        recipient,
        id,
        transfer_amount,
    );
}

#[test]
unconstrained fn transfer_public_to_private_on_behalf_of_other() {
    // Proxy + private authwit + 5-arg forward.
    let (env, multitoken_contract_address, owner, recipient, _, proxy) =
        utils::setup_and_mint_to_public_with_proxy(1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (2 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_public_to_private(
        owner,
        recipient,
        id,
        transfer_amount,
        0,
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

    utils::check_public_balance(
        env,
        multitoken_contract_address,
        owner,
        id,
        mint_amount - transfer_amount,
    );
    utils::check_private_balance(
        env,
        multitoken_contract_address,
        recipient,
        id,
        transfer_amount,
    );
}

// Public underflow fires in the enqueued decrease_public_balance_internal -> _decrease_public_balance (main.nr:565).
#[test(should_fail_with = "attempt to subtract with overflow 'self.storage.public_balances.at(id).at(owner).read() - amount'")]
unconstrained fn transfer_public_to_private_failure_more_than_balance() {
    // Public debit exceeding balance underflows.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount * (2 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_public_to_private(
            owner,
            recipient,
            id,
            transfer_amount,
            0,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn transfer_public_to_private_failure_on_behalf_of_other_without_approval() {
    // Proxy with NO authwit reverts on the missing private authwit.
    let (env, multitoken_contract_address, owner, recipient, _, proxy) =
        utils::setup_and_mint_to_public_with_proxy(1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (2 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_public_to_private(
        owner,
        recipient,
        id,
        transfer_amount,
        0,
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
