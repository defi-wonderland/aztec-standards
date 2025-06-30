
use crate::Dripper;
use aztec::{
    prelude::AztecAddress,
    test::helpers::{cheatcodes, test_environment::TestEnvironment},
};
use token::Token;

pub global drip_amount: u64 = 1000;

pub unconstrained fn setup_dripper_and_token(
    with_account_contracts: bool,
) -> (&mut TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let (alice, bob, minter) = if with_account_contracts {
        let alice = env.create_account_contract(1);
        let bob = env.create_account_contract(2);
        let minter = env.create_account_contract(3);
        (alice, bob, minter)
    } else {
        let alice = env.create_account(1);
        let bob = env.create_account(2);
        let minter = env.create_account(3);
        (alice, bob, minter)
    };

    // Deploy token contract with minter
    let token_contract_address = deploy_token_with_minter(&mut env, alice, minter);
    
    // Deploy dripper contract
    let dripper_contract_address = deploy_dripper(&mut env, alice);

    (&mut env, token_contract_address, dripper_contract_address, alice, bob)
}

pub unconstrained fn deploy_token_with_minter(
    env: &mut TestEnvironment,
    owner: AztecAddress,
    minter: AztecAddress,
) -> AztecAddress {
    // Start the test in the account contract address
    env.impersonate(owner);

    // Deploy token contract
    let initializer_call_interface = Token::interface().constructor_with_minter(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
        minter,
        AztecAddress::zero(),
    );
    let token_contract = env.deploy("./@token_contract", "Token").with_public_void_initializer(
        owner,
        initializer_call_interface,
    );
    env.advance_block_by(1);

    token_contract.to_address()
}

pub unconstrained fn deploy_dripper(
    env: &mut TestEnvironment,
    owner: AztecAddress,
) -> AztecAddress {
    // Start the test in the account contract address
    env.impersonate(owner);

    // Deploy dripper contract
    let initializer_call_interface = Dripper::interface().constructor();
    let dripper_contract = env.deploy("./@dripper", "Dripper").with_public_void_initializer(
        owner,
        initializer_call_interface,
    );
    env.advance_block_by(1);

    dripper_contract.to_address()
}

pub unconstrained fn check_public_balance(
    token_contract_address: AztecAddress,
    address: AztecAddress,
    expected_amount: u128,
) {
    let balance = Token::at(token_contract_address).balance_of_public(address).view(&mut TestEnvironment::new().public());
    assert(balance == expected_amount, "Public balance is not correct");
}

pub unconstrained fn check_private_balance(
    token_contract_address: AztecAddress,
    address: AztecAddress,
    expected_amount: u128,
) {
    let balance = Token::at(token_contract_address).balance_of_private(address).view(&mut TestEnvironment::new().private());
    assert(balance == expected_amount, "Private balance is not correct");
}

pub unconstrained fn check_total_supply(
    token_contract_address: AztecAddress,
    expected_total_supply: u128,
) {
    let total_supply = Token::at(token_contract_address).total_supply().view(&mut TestEnvironment::new().public());
    assert(total_supply == expected_total_supply, "Total supply is not correct");
}

