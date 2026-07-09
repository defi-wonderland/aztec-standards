use crate::MultiToken;
use crate::test::utils::{self, mint_amount};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

#[test]
unconstrained fn transfer_private_to_commitment_success() {
    // Initialize a commitment with completer = owner (msg_sender at completion), then
    // transfer from the owner's private balance into it. Owner debits; recipient's private balance credits.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_private_with_minter(false, 1);

    let commitment = env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_commitment(
            owner,
            id,
            commitment,
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
unconstrained fn transfer_private_to_commitment_on_behalf_of_other() {
    // The commitment's completer must be the proxy (msg_sender in the token when forwarded).
    let (env, multitoken_contract_address, owner, recipient, _, proxy) =
        utils::setup_and_mint_to_private_with_proxy(1);

    let commitment = env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(recipient, proxy),
    );

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_private_to_commitment(
        owner,
        id,
        commitment,
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

#[test(should_fail_with = "is reading an unknown nullifier")]
unconstrained fn transfer_private_to_commitment_failure_wrong_completer() {
    // Commitment initialized with completer = recipient, but owner completes it; the
    // private path (complete_from_private) checks the settled validity nullifier, which does not exist for `owner`.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_private_with_minter(false, 1);

    let commitment = env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(
            recipient,
            recipient,
        ),
    );

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_commitment(
            owner,
            id,
            commitment,
            transfer_amount,
            0,
        ),
    );
}

#[test(should_fail_with = "Balance too low")]
unconstrained fn transfer_private_to_commitment_failure_more_than_balance() {
    // The private debit precedes completion, so an over-balance debit reverts "Balance too low".
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_private_with_minter(false, 1);

    let commitment = env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    let id: Field = 1;
    let transfer_amount = mint_amount + (1 as u128);
    env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_private_to_commitment(
            owner,
            id,
            commitment,
            transfer_amount,
            0,
        ),
    );
}
