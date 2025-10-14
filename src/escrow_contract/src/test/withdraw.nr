use crate::Escrow;
use crate::test::utils as escrow_utils;
use aztec::oracle::get_contract_instance::get_contract_instance;
use aztec::protocol_types::{address::AztecAddress, traits::FromField};
use token::{test::utils as token_utils, Token};

// TODO: Fix error "No public key registered for address 0x0000000000000000000000000000000000000000000000000000000000000001."
// Previously, with env.impersonate(any address) we could impersonate any address even if it didn't have keys,
// but now with env.call_private(any address, ...) it is not possible.
// The sender must have keys and the address must be registered in PXE like this. 
// Because the escrow contract cannot be deployed with the salt that we want yet, 
// it defaults to address 0x1 which we don't know the secret of.
// #[test]
unconstrained fn escrow_withdraw_success() {
    let escrow_secret: Field = 123456;
    let (mut env, escrow_contract_address, token_contract_address, _, _, recipient, minter) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    let escrow_instance = get_contract_instance(escrow_contract_address);
    let logic_contract_address = AztecAddress::from_field(escrow_instance.salt);

    // Mint some tokens to escrow
    let amount: u128 = token_utils::mint_amount;
    env.call_private(
        minter,
        Token::at(token_contract_address).mint_to_private(minter, escrow_contract_address, amount),
    );

    // Check the escrow received and can read the tokens
    token_utils::check_private_balance(
        env,
        token_contract_address,
        escrow_contract_address,
        amount,
    );

    env.call_private(
        logic_contract_address,
        Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient),
    );

    // Check recipient got tokens
    token_utils::check_private_balance(env, token_contract_address, recipient, amount);
}

// #[test]
unconstrained fn escrow_withdraw_twice_success() {
    let escrow_secret: Field = 123456;
    let (mut env, escrow_contract_address, token_contract_address, _, _, recipient, minter) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    let escrow_instance = get_contract_instance(escrow_contract_address);
    let logic_contract_address = AztecAddress::from_field(escrow_instance.salt);

    // Mint some tokens to escrow
    let total_amount: u128 = token_utils::mint_amount * 2;
    env.call_private(
        minter,
        Token::at(token_contract_address).mint_to_private(
            minter,
            escrow_contract_address,
            total_amount,
        ),
    );

    // Check the escrow received and can read the tokens
    token_utils::check_private_balance(
        env,
        token_contract_address,
        escrow_contract_address,
        total_amount,
    );

    let amount: u128 = token_utils::mint_amount;
    // Partial withdrawal
    env.call_private(
        logic_contract_address,
        Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient),
    );

    // Check balances
    token_utils::check_private_balance(env, token_contract_address, recipient, amount);
    token_utils::check_private_balance(
        env,
        token_contract_address,
        escrow_contract_address,
        amount,
    );

    // Complete withdrawal
    env.call_private(
        logic_contract_address,
        Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient),
    );

    // Check balances
    token_utils::check_private_balance(env, token_contract_address, recipient, total_amount);
    token_utils::check_private_balance(env, token_contract_address, escrow_contract_address, 0);
}

#[test(should_fail_with = "Not Authorized")]
unconstrained fn escrow_withdraw_unauthorized() {
    let escrow_secret: Field = 123456;
    let (mut env, escrow_contract_address, token_contract_address, _, owner, recipient, _) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    let amount: u128 = token_utils::mint_amount;
    env.call_private(
        owner,
        Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient),
    );
}
