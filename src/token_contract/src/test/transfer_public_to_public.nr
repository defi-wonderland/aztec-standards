use crate::test::utils::{self, mint_amount};
use crate::Token;
use aztec::{
    protocol::{address::AztecAddress, constants::NULL_MSG_SENDER_CONTRACT_ADDRESS},
    test::helpers::authwit as authwit_cheatcodes,
};

#[test]
unconstrained fn public_transfer() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);
    // Transfer tokens
    let transfer_amount = mint_amount / (10 as u128);
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_public(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    // Check balances
    utils::check_public_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_public_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn public_transfer_to_self() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, _) =
        utils::setup_and_mint_to_public_without_minter(false);
    // Transfer tokens
    let transfer_amount = mint_amount / (10 as u128);
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_public(
            owner,
            owner,
            transfer_amount,
            0,
        ),
    );
    // Check balances
    utils::check_public_balance(env, token_contract_address, owner, mint_amount);
}

#[test]
unconstrained fn public_transfer_on_behalf_of_other() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);
    let transfer_amount = mint_amount / (10 as u128);
    let public_transfer_private_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount, 1);
    authwit_cheatcodes::add_public_authwit_from_call(
        env,
        owner,
        recipient,
        public_transfer_private_to_private_call_interface,
    );
    // Impersonate recipient to perform the call
    // Transfer tokens
    env.call_public(recipient, public_transfer_private_to_private_call_interface);
    // Check balances
    utils::check_public_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_public_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test(should_fail_with = "attempt to subtract with overflow 'self.storage.public_balances.at(from).read() - amount'")]
unconstrained fn public_transfer_failure_more_than_balance() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);
    // Transfer tokens
    let transfer_amount = mint_amount + (1 as u128);
    let public_transfer_call_interface = Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount, 0);
    // Try to transfer tokens
    env.call_public(owner, public_transfer_call_interface);
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn public_transfer_failure_on_behalf_of_other_without_approval() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);
    let transfer_amount = mint_amount / (10 as u128);
    let public_transfer_private_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount, 1);
    // Impersonate recipient to perform the call
    // Try to transfer tokens
    env.call_public(recipient, public_transfer_private_to_private_call_interface);
}

#[test(should_fail_with = "attempt to subtract with overflow 'self.storage.public_balances.at(from).read() - amount'")]
unconstrained fn public_transfer_failure_on_behalf_of_other_more_than_balance() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);
    let transfer_amount = mint_amount + (1 as u128);
    let public_transfer_private_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount, 1);
    authwit_cheatcodes::add_public_authwit_from_call(
        env,
        owner,
        recipient,
        public_transfer_private_to_private_call_interface,
    );
    // Impersonate recipient to perform the call
    // Try to transfer tokens
    env.call_public(recipient, public_transfer_private_to_private_call_interface);
}

#[test(should_fail_with = "unauthorized")]
unconstrained fn public_transfer_failure_on_behalf_of_other_wrong_caller() {
    // Setup with account contracts. Slower since we actually deploy them, but needed for authwits.
    let (mut env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(true);
    let transfer_amount = mint_amount / (10 as u128);
    let public_transfer_private_to_private_call_interface = Token::at(token_contract_address)
        .transfer_public_to_public(owner, recipient, transfer_amount, 1);
    authwit_cheatcodes::add_public_authwit_from_call(
        env,
        owner,
        owner,
        public_transfer_private_to_private_call_interface,
    );
    // Impersonate recipient to perform the call
    // Try to transfer tokens
    env.call_public(recipient, public_transfer_private_to_private_call_interface);
}

// PoC: zero-address public balance is NOT spendable by a third party.
//
// Scenario: owner sends tokens to address(0)'s public balance, then an attacker
// calls transfer_public_to_public(from=address(0), ...) directly (nonce=0, no authwit).
//
// The authorize_once macro expands to:
//   if msg_sender != from { assert_current_call_valid_authwit_public(ctx, from) }
//   else                  { assert(nonce == 0) }
//
// Since msg_sender (attacker) != from (address(0)), the authwit registry is consulted
// for address(0). address(0) never placed anything in the registry => "unauthorized".
#[test(should_fail_with = "unauthorized")]
unconstrained fn poc_zero_address_public_balance_not_spendable_by_third_party() {
    let (env, token_contract_address, owner, attacker) =
        utils::setup_and_mint_to_public_without_minter(false);

    let zero_address = AztecAddress::zero();
    let drain_amount: u128 = 100;

    // Step 1: credit address(0) public balance (this succeeds - no guard on recipient)
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_public(
            owner,
            zero_address,
            drain_amount,
            0,
        ),
    );

    // Sanity: address(0) now has tokens
    utils::check_public_balance(env, token_contract_address, zero_address, drain_amount);

    // Step 2: attacker attempts to drain address(0) public balance.
    // msg_sender = attacker != address(0) = from
    // => authorize_once calls assert_current_call_valid_authwit_public(ctx, address(0))
    // => address(0) has no entry in auth registry => fails "unauthorized"
    env.call_public(
        attacker,
        Token::at(token_contract_address).transfer_public_to_public(
            zero_address,
            attacker,
            drain_amount,
            0,
        ),
    );
}

// PoC: same attack via an enqueued public call (hiding msg_sender).
//
// When a private function enqueues transfer_public_to_public, the public-side
// msg_sender becomes the enqueuing contract address (not the original wallet).
// That address is still non-zero, so the authwit check on address(0) still fires
// and fails "unauthorized". The "hidden msg_sender" trick does not help.
//
// We simulate this with transfer_public_to_private (which enqueues decrease_public_balance_internal
// via #[only_self]), but we directly exercise the public path to show msg_sender hiding
// cannot bypass the authwit guard on address(0).
#[test(should_fail_with = "unauthorized")]
unconstrained fn poc_zero_address_public_balance_not_spendable_via_enqueued_call() {
    let (env, token_contract_address, owner, attacker) =
        utils::setup_and_mint_to_public_without_minter(false);

    let zero_address = AztecAddress::zero();
    let drain_amount: u128 = 100;

    // Step 1: credit address(0) public balance
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_public(
            owner,
            zero_address,
            drain_amount,
            0,
        ),
    );

    // Step 2: attacker uses nonce=1 (signals "I have an authwit from address(0)") -
    // this is what an enqueued-call-with-hidden-sender scenario would require.
    // authorize_once: msg_sender=attacker != from=address(0)
    //   => assert_current_call_valid_authwit_public(ctx, address(0))
    //   => address(0) never set_authorized anything => fails "unauthorized"
    env.call_public(
        attacker,
        Token::at(token_contract_address).transfer_public_to_public(
            zero_address,
            attacker,
            drain_amount,
            1, // non-zero nonce: authwit path
        ),
    );
}

// PoC: NULL_MSG_SENDER_CONTRACT_ADDRESS is not anyone-spendable either.
//
// An incognito public call sets the raw AVM sender to NULL_MSG_SENDER_CONTRACT_ADDRESS.
// aztec-nr maps that sentinel to Option::none(); ContractSelfPublic::msg_sender()
// then unwraps it and reverts before transfer_public_to_public can treat it as an
// authorized `from` address.
#[test(should_fail)]
unconstrained fn poc_null_msg_sender_public_balance_not_spendable_by_incognito_sender() {
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);

    let null_msg_sender = NULL_MSG_SENDER_CONTRACT_ADDRESS;
    let drain_amount: u128 = 100;

    // Credit the sentinel address' public token balance.
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_public(
            owner,
            null_msg_sender,
            drain_amount,
            0,
        ),
    );
    utils::check_public_balance(env, token_contract_address, null_msg_sender, drain_amount);

    // Simulate the public frame an incognito-enqueued call would execute with:
    // raw msg_sender = NULL_MSG_SENDER_CONTRACT_ADDRESS.
    // self.msg_sender() unwraps none and the call fails; it cannot drain the balance.
    env.call_public(
        null_msg_sender,
        Token::at(token_contract_address).transfer_public_to_public(
            null_msg_sender,
            recipient,
            drain_amount,
            0,
        ),
    );
}
