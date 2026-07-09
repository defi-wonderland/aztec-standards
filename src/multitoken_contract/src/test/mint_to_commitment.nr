use crate::MultiToken;
use crate::test::utils::{self, mint_amount};
use aztec::oracle::random::random;

#[test]
unconstrained fn mint_to_commitment_success() {
    // Initialize a commitment with completer = minter (msg_sender at completion), then mint into it.
    let (env, multitoken_contract_address, _, recipient, minter) = utils::setup_with_minter(false);

    let commitment = env.call_private(
        minter,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(
            recipient,
            minter,
        ),
    );

    let id: Field = 1;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_commitment(id, commitment, mint_amount),
    );

    utils::check_private_balance(env, multitoken_contract_address, recipient, id, mint_amount);
}

#[test(should_fail_with = "caller is not minter")]
unconstrained fn mint_to_commitment_failure_as_non_minter() {
    // A non-minter completing a commitment via mint_to_commitment must revert.
    let (env, multitoken_contract_address, _, recipient, _) = utils::setup_with_minter(false);

    let commitment = env.call_private(
        recipient,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(
            recipient,
            recipient,
        ),
    );

    let id: Field = 1;
    env.call_public(
        recipient,
        MultiToken::at(multitoken_contract_address).mint_to_commitment(id, commitment, mint_amount),
    );
}

#[test(should_fail_with = "Invalid partial note or completer")]
unconstrained fn mint_to_commitment_failure_invalid_commitment() {
    // Completing a random (uninitialized) commitment fails the public-path validity check.
    let (env, multitoken_contract_address, _, _, minter) = utils::setup_with_minter(false);

    let id: Field = 1;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_commitment(id, random(), mint_amount),
    );
}

#[test]
unconstrained fn mint_to_commitment_id_zero_success() {
    // The zero-guard is on `value` not `id`: completing with id = 0, amount > 0 succeeds.
    let (env, multitoken_contract_address, _, recipient, minter) = utils::setup_with_minter(false);

    let commitment = env.call_private(
        minter,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(
            recipient,
            minter,
        ),
    );

    let id: Field = 0;
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_commitment(id, commitment, mint_amount),
    );

    utils::check_private_balance(env, multitoken_contract_address, recipient, id, mint_amount);
}
