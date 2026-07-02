use crate::MultiToken;
use crate::test::utils::{self, mint_amount};
use aztec::oracle::random::random;

#[test]
unconstrained fn transfer_public_to_commitment_success() {
    // Initialize a commitment (completer = owner), then move from the owner's PUBLIC
    // balance into it. Owner's public balance debits; recipient's PRIVATE balance credits.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(false, 1);

    let commitment = env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    env.call_public(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_public_to_commitment(
            owner,
            id,
            commitment,
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

#[test(should_fail_with = "Invalid partial note or completer")]
unconstrained fn transfer_public_to_commitment_failure_not_initialized() {
    // With sufficient public balance the debit succeeds, so the public-path complete fails on a
    // random (uninitialized) commitment.
    let (env, multitoken_contract_address, owner, _, _) =
        utils::setup_and_mint_to_public_with_minter(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    // Commitment was never initialized.
    env.call_public(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_public_to_commitment(
            owner,
            id,
            random(),
            transfer_amount,
            0,
        ),
    );
}

// Public underflow expression from MultiToken main.nr:565 (`_decrease_public_balance`); the debit precedes completion.
#[test(should_fail_with = "attempt to subtract with overflow 'self.storage.public_balances.at(id).at(owner).read() - amount'")]
unconstrained fn transfer_public_to_commitment_failure_more_than_balance() {
    // The public debit precedes completion, so an over-balance debit underflows first.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(false, 1);

    let commitment = env.call_private(
        owner,
        MultiToken::at(multitoken_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    let id: Field = 1;
    let transfer_amount = mint_amount + (1 as u128);
    env.call_public(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_public_to_commitment(
            owner,
            id,
            commitment,
            transfer_amount,
            0,
        ),
    );
}
