use crate::MultiToken;
use crate::test::utils::{self, mint_amount};
use aztec::test::helpers::authwit as authwit_cheatcodes;

#[test]
unconstrained fn transfer_public_to_public_success() {
    // Both endpoints move by transfer_amount.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    env.call_public(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_public_to_public(
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
    utils::check_public_balance(
        env,
        multitoken_contract_address,
        recipient,
        id,
        transfer_amount,
    );
}

#[test]
unconstrained fn transfer_public_to_public_to_self() {
    // owner -> owner leaves the balance unchanged.
    let (env, multitoken_contract_address, owner, _, _) =
        utils::setup_and_mint_to_public_with_minter(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    env.call_public(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_public_to_public(
            owner,
            owner,
            id,
            transfer_amount,
            0,
        ),
    );

    utils::check_public_balance(env, multitoken_contract_address, owner, id, mint_amount);
}

#[test]
unconstrained fn transfer_public_to_public_on_behalf_of_other() {
    // Public authwit uses a second account as caller (no proxy needed for public).
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(true, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_public_to_public(
        owner,
        recipient,
        id,
        transfer_amount,
        1,
    );
    authwit_cheatcodes::add_public_authwit_from_call(env, owner, recipient, call_interface);
    // Recipient (caller != from) performs the call.
    env.call_public(recipient, call_interface);

    utils::check_public_balance(
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

// Public underflow expression derived from MultiToken main.nr:565 (`_decrease_public_balance`); keyed (id, owner).
#[test(should_fail_with = "attempt to subtract with overflow 'self.storage.public_balances.at(id).at(owner).read() - amount'")]
unconstrained fn transfer_public_to_public_failure_more_than_balance() {
    // Transferring more than balance underflows the public balance.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(false, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount + (1 as u128);
    env.call_public(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_public_to_public(
            owner,
            recipient,
            id,
            transfer_amount,
            0,
        ),
    );
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn transfer_public_to_public_failure_on_behalf_of_other_without_approval() {
    // caller != from with NO authwit must be rejected by the public authwit check.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(true, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_public_to_public(
        owner,
        recipient,
        id,
        transfer_amount,
        1,
    );
    // No authwit added; recipient impersonates the call.
    env.call_public(recipient, call_interface);
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn transfer_public_to_public_failure_on_behalf_of_other_wrong_caller() {
    // Authwit granted to `owner` (not the actual caller `recipient`) must still be rejected.
    let (env, multitoken_contract_address, owner, recipient, _) =
        utils::setup_and_mint_to_public_with_minter(true, 1);

    let id: Field = 1;
    let transfer_amount = mint_amount / (10 as u128);
    let call_interface = MultiToken::at(multitoken_contract_address).transfer_public_to_public(
        owner,
        recipient,
        id,
        transfer_amount,
        1,
    );
    // Authwit added for the wrong designated caller (owner instead of recipient).
    authwit_cheatcodes::add_public_authwit_from_call(env, owner, owner, call_interface);
    env.call_public(recipient, call_interface);
}

#[test]
unconstrained fn transfer_public_to_public_per_id_isolation() {
    // Owner holds (idX, a) and (idY, b) public; transferring some of idX leaves idY intact.
    let (env, multitoken_contract_address, owner, recipient, minter) =
        utils::setup_and_mint_to_public_with_minter(false, 1);

    let id_x: Field = 1;
    let id_y: Field = 2;
    let amount_y: u128 = 3_000;
    // Mint a second id to the owner's public balance.
    env.call_public(
        minter,
        MultiToken::at(multitoken_contract_address).mint_to_public(owner, id_y, amount_y),
    );

    let transfer_amount = mint_amount / (10 as u128);
    env.call_public(
        owner,
        MultiToken::at(multitoken_contract_address).transfer_public_to_public(
            owner,
            recipient,
            id_x,
            transfer_amount,
            0,
        ),
    );

    // idY balance of the owner is untouched.
    utils::check_public_balance(env, multitoken_contract_address, owner, id_y, amount_y);
    utils::check_public_balance(
        env,
        multitoken_contract_address,
        owner,
        id_x,
        mint_amount - transfer_amount,
    );
}
