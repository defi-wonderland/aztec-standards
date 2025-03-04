use crate::FeeOnTransferToken;
use aztec::{
    oracle::{
        execution::{get_block_number, get_contract_address},
        random::random,
        storage::storage_read,
    },
    prelude::AztecAddress,
    protocol_types::storage::map::derive_storage_slot_in_map,
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
};
use std::test::OracleMock;

pub unconstrained fn setup() -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();

    let owner = env.create_account_contract(1);
    let sender = env.create_account_contract(2);
    let recipient = env.create_account_contract(3);

    // Start the test in the account contract address
    env.impersonate(owner);

    // Deploy token contract
    let initializer_call_interface = FeeOnTransferToken::interface().constructor(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
        owner,
    );
    let token_contract = env.deploy_self("FeeOnTransferToken").with_public_void_initializer(
        initializer_call_interface,
    );
    let token_contract_address = token_contract.to_address();
    env.advance_block_by(1);
    (&mut env, token_contract_address, owner, sender, recipient)
}

pub unconstrained fn mint_to_private(
    env: &mut TestEnvironment,
    token_contract_address: AztecAddress,
    recipient: AztecAddress,
    amount: U128,
) {
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    let from = recipient; // we are setting from to recipient because of TODO(#9887)
    FeeOnTransferToken::at(token_contract_address).mint_to_private(from, recipient, amount).call(
        &mut env.private(),
    );

    env.advance_block_by(1);
}

pub unconstrained fn mint_to_public(
    env: &mut TestEnvironment,
    token_contract_address: AztecAddress,
    recipient: AztecAddress,
    amount: U128,
) {
    FeeOnTransferToken::at(token_contract_address).mint_to_public(recipient, amount).call(
        &mut env.public(),
    );

    env.advance_block_by(1);
}

pub unconstrained fn check_public_balance(
    token_contract_address: AztecAddress,
    address: AztecAddress,
    address_amount: U128,
) {
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(token_contract_address);
    let block_number = get_block_number();

    let balances_slot = FeeOnTransferToken::storage_layout().public_balances.slot;
    let address_slot = derive_storage_slot_in_map(balances_slot, address);
    let amount: U128 = storage_read(token_contract_address, address_slot, block_number);
    assert(amount == address_amount, "Public balance is not correct");
    cheatcodes::set_contract_address(current_contract_address);
}

pub unconstrained fn check_private_balance(
    token_contract_address: AztecAddress,
    address: AztecAddress,
    address_amount: U128,
) {
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(token_contract_address);
    // Direct call to unconstrained
    let balance_of_private = FeeOnTransferToken::balance_of_private(address);
    assert(balance_of_private == address_amount, "Private balance is not correct");
    cheatcodes::set_contract_address(current_contract_address);
}
