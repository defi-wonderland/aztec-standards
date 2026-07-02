use crate::MultiToken;
use crate::test::utils::{self, mint_amount};

#[test]
unconstrained fn initialize_transfer_commitment_no_id_param_and_no_hook() {
    // The signature is (to, completer) with NO id, and it spends nothing, so it must NOT fire the
    // authorization hook (pair with a wired spy + assert_auth_not_called).
    let (env, multitoken_contract_address, owner, recipient, _, auth_contract) =
        utils::setup_with_auth_contract_and_minter(false);

    // Returns a Field commitment; note the call takes only (to, completer) - no id parameter.
    let _commitment = env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    utils::assert_auth_not_called(env, auth_contract);
}

#[test]
unconstrained fn initialize_transfer_commitment_completer_binds_id_at_completion() {
    // Initialize ONE commitment (no id at init), then the completer chooses the id at
    // completion via mint_to_commitment(idChosen, ...). This is the intentional id-binding-at-completion property.
    let (env, multitoken_contract_address, _, recipient, minter) = utils::setup_with_minter(false);

    let commitment = env.call_private(
        minter,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(
            recipient,
            minter,
        ),
    );

    let id_chosen: Field = 7;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_commitment(
            id_chosen,
            commitment,
            mint_amount,
        ),
    );

    utils::check_private_balance(
        env,
        multitoken_contract_address,
        recipient,
        id_chosen,
        mint_amount,
    );
}
