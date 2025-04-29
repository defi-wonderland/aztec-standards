use crate::{test::utils, Token};
use authwit::cheatcodes as authwit_cheatcodes;
use aztec::oracle::random::random;
use bignum_field::{bignum_field::BigNumField, bignum_field_note::BigNumFieldNote};
use bignum_field::bignum_field_note::PartialBigNumFieldNote;

use std::test::OracleMock;
use uint_note::uint_note::{PartialUintNote, UintNote};

#[test]
unconstrained fn transfer_public_to_private_success() {
    let (env, token_contract_address, sender, recipient, mint_amount) =
        utils::setup_and_mint_to_public_without_minter(false);

    utils::check_public_balance(token_contract_address, sender, mint_amount);
    utils::check_private_balance(token_contract_address, recipient, BigNumField::zero());

    let nonce = 0;
    let transfer_amount = mint_amount / BigNumField::new(2);

    let note_randomness = random();

    // We mock the Oracle to return the note randomness such that later on we can manually add the note
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    // We prepare the transfer
    let partial_note: PartialBigNumFieldNote = Token::at(token_contract_address)
        .initialize_transfer_commitment(sender, recipient)
        .call(&mut env.private());

    // Finalize the transfer of the tokens (message sender owns the tokens in public)
    Token::at(token_contract_address)
        .transfer_public_to_commitment(sender, transfer_amount, partial_note, 0)
        .call(&mut env.public());

    env.advance_block_by(1);

    // sender public balance decreases
    utils::check_public_balance(token_contract_address, sender, transfer_amount);
    // recipient private balance incre ases
    utils::check_private_balance(token_contract_address, recipient, transfer_amount);
}

// #[test(should_fail_with = "transfer not prepared")]
// unconstrained fn transfer_public_to_private_transfer_not_prepared() {
//     // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
//     let (env, token_contract_address, owner, _, amount) =
//         utils::setup_and_mint_to_public_without_minter(/* with_account_contracts */ false);

//     // Transfer was not prepared so we can use random value for the hiding point slot
//     let hiding_point_slot = random();

//     // Try finalizing the transfer without preparing it
//     Token::at(token_contract_address)
//         .finalize_transfer_public_to_private(owner, amount, hiding_point_slot, 0)
//         .call(&mut env.public());
// }

// #[test(should_fail_with = "Assertion failed: attempt to subtract with underflow 'hi == high'")]
#[test(should_fail_with = "Assertion failed: U256 subtraction underflow")]
unconstrained fn transfer_public_to_private_failure_not_an_owner() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, not_owner, amount) =
        utils::setup_and_mint_to_public_without_minter(/* with_account_contracts */ false);

    // (For this specific test we could set a random value for the commitment and not do the call to `prepare...`
    // as the token balance check is before we use the value but that would made the test less robust against changes
    // in the contract.)
    let partial_note: PartialBigNumFieldNote = Token::at(token_contract_address)
        .initialize_transfer_commitment(owner, not_owner)
        .call(&mut env.private());

    // Try transferring someone else's token balance
    env.impersonate(not_owner);
    Token::at(token_contract_address)
        .transfer_public_to_commitment(not_owner, amount, partial_note, 0)
        .call(&mut env.public());
}
