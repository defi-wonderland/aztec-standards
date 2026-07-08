use crate::MultiToken;
use crate::test::utils::{self, mint_amount};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

#[test]
unconstrained fn transfer_private_to_private_on_behalf_of_self() {
    // Both endpoints move by transfer_amount.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_private_with_minter(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_private(
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
    utils::check_private_balance(
        env,
        multitoken_contract_address,
        recipient,
        id,
        transfer_amount,
    );
}

#[test]
unconstrained fn transfer_private_to_private_on_behalf_of_other() {
    // Proxy makes msg_sender != from, triggering private authwit validation. 5-arg transfer.
    let (env, multitoken_contract_address, owner, recipient, _, proxy) =
        utils::setup_and_mint_to_private_with_proxy(1);

    let id: Field = 1;
    let transfer_amount = (1_000 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_private_to_private(
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
    utils::check_private_balance(
        env,
        multitoken_contract_address,
        recipient,
        id,
        transfer_amount,
    );
}

#[test]
unconstrained fn transfer_private_to_private_zero_amount() {
    // amount = 0 creates no note (add no-ops on 0); balances unchanged.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_private_with_minter(false, 1);

    let id: Field = 1;
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_private(
            owner,
            recipient,
            id,
            0 as u128,
            0,
        ),
    );

    utils::check_private_balance(env, multitoken_contract_address, owner, id, mint_amount);
    utils::check_private_balance(env, multitoken_contract_address, recipient, id, 0 as u128);
}

#[test]
unconstrained fn transfer_private_to_private_change_recredit_same_id() {
    // Two notes of `id` sum to more than the transfer; the change is re-credited as a
    // SAME-id note. Owner residual = sum - amount; recipient = amount.
    let (env, multitoken_contract_address, owner, recipient, minter) =
        utils::setup_with_minter(false);

    let id: Field = 1;
    let note_a: u128 = 6_000;
    let note_b: u128 = 4_000;
    utils::mint_to_private(env, multitoken_contract_address, owner, id, note_a, minter);
    utils::mint_to_private(env, multitoken_contract_address, owner, id, note_b, minter);

    let transfer_amount: u128 = 7_000;
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_private(
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
        note_a + note_b - transfer_amount,
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
unconstrained fn transfer_private_to_private_multiple_notes_recursively() {
    // 12 notes of `id` force cross-frame recursion (2 + 8 + 1) in _subtract_balance.
    let (env, multitoken_contract_address, owner, recipient, minter) =
        utils::setup_with_minter(false);

    let id: Field = 1;
    let notes_amount: u128 = 1_000;
    let notes_count: u128 = 12;
    let total_amount = notes_amount * notes_count;

    for _ in 0..notes_count {
        utils::mint_to_private(
            env,
            multitoken_contract_address,
            owner,
            id,
            notes_amount,
            minter,
        );
    }

    // Transfer 10999 of 12000: requires 11 notes with change -> 2 recursive frames (2 + 8 + 1).
    let transfer_amount = total_amount - notes_amount - (1 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_private(
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
        total_amount - transfer_amount,
    );
    utils::check_private_balance(
        env,
        multitoken_contract_address,
        recipient,
        id,
        transfer_amount,
    );
}

#[test(should_fail_with = "Balance too low")]
unconstrained fn transfer_private_to_private_failure_more_than_balance() {
    // Transferring more than balance (on-behalf via proxy + authwit) reverts "Balance too low".
    let (env, multitoken_contract_address, owner, recipient, _, proxy) =
        utils::setup_and_mint_to_private_with_proxy(1);

    let id: Field = 1;
    let transfer_amount = mint_amount + (1 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_private_to_private(
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
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn transfer_private_to_private_failure_on_behalf_of_other_without_approval() {
    // Proxy with NO authwit must revert on the missing private authwit.
    let (env, multitoken_contract_address, owner, recipient, _, proxy) =
        utils::setup_and_mint_to_private_with_proxy(1);

    let id: Field = 1;
    let transfer_amount = (1_000 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_private_to_private(
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

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn transfer_private_to_private_failure_on_behalf_of_other_wrong_caller() {
    // Authwit granted to `owner` (not the proxy) must still revert.
    let (env, multitoken_contract_address, owner, recipient, _, proxy) =
        utils::setup_and_mint_to_private_with_proxy(1);

    let id: Field = 1;
    let transfer_amount = (1_000 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_private_to_private(
        owner,
        recipient,
        id,
        transfer_amount,
        1,
    );
    // Authwit added for the wrong caller (owner instead of proxy).
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, owner, call_interface);
    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_5(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );
}

#[test]
unconstrained fn transfer_private_to_private_per_id_isolation() {
    // Owner holds (idX, a),(idY, b) private; transferring idX leaves idY intact
    // (constrained select(token_id == idX)).
    let (env, multitoken_contract_address, owner, recipient, minter) =
        utils::setup_with_minter(false);

    let id_x: Field = 1;
    let id_y: Field = 2;
    let amount_x: u128 = 5_000;
    let amount_y: u128 = 3_000;
    utils::mint_to_private(
        env,
        multitoken_contract_address,
        owner,
        id_x,
        amount_x,
        minter,
    );
    utils::mint_to_private(
        env,
        multitoken_contract_address,
        owner,
        id_y,
        amount_y,
        minter,
    );

    let transfer_amount: u128 = 2_000;
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_private(
            owner,
            recipient,
            id_x,
            transfer_amount,
            0,
        ),
    );

    utils::check_private_balance(env, multitoken_contract_address, owner, id_y, amount_y);
    utils::check_private_balance(
        env,
        multitoken_contract_address,
        owner,
        id_x,
        amount_x - transfer_amount,
    );
    utils::check_private_balance(
        env,
        multitoken_contract_address,
        recipient,
        id_x,
        transfer_amount,
    );
}

#[test]
unconstrained fn transfer_private_to_private_no_public_side_effect() {
    // A fully-private transfer writes no public balance.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_private_with_minter(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_private(
            owner,
            recipient,
            id,
            transfer_amount,
            0,
        ),
    );

    utils::check_public_balance(env, multitoken_contract_address, owner, id, 0 as u128);
    utils::check_public_balance(env, multitoken_contract_address, recipient, id, 0 as u128);
}
