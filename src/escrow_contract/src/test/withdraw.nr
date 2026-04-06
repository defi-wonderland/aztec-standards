use crate::Escrow;
use crate::test::utils as escrow_utils;
use token::{test::utils as token_utils, Token};

// TODO (reenable test): TXE scope enforcement means only the `from` address's notes are accessible during
// private execution. The escrow's token notes are not in scope when called from logic_contract_address.
// The TS tests handle this via `additionalScopes: [escrow.address]`, but TXE doesn't support it yet.
// See: https://github.com/AztecProtocol/aztec-packages/blob/v4.2.0-aztecnr-rc.2/noir-projects/aztec-nr/aztec/src/test/helpers/test_environment.nr#L953-L954
#[allow(dead_code)]
unconstrained fn escrow_withdraw_success() {
    let escrow_secret: Field = 123456;
    let (mut env, escrow_contract_address, token_contract_address, _, _, recipient, minter, logic_contract_address) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    // Mint some tokens to escrow
    let amount: u128 = token_utils::mint_amount;
    env.call_private(
        minter,
        Token::at(token_contract_address).mint_to_private(escrow_contract_address, amount),
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

// TODO (reenable test): same TXE scope enforcement issue as escrow_withdraw_success (see comment above).
#[allow(dead_code)]
unconstrained fn escrow_withdraw_twice_success() {
    let escrow_secret: Field = 123456;
    let (mut env, escrow_contract_address, token_contract_address, _, _, recipient, minter, logic_contract_address) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    // Mint some tokens to escrow
    let total_amount: u128 = token_utils::mint_amount * 2;
    env.call_private(
        minter,
        Token::at(token_contract_address).mint_to_private(escrow_contract_address, total_amount),
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
    let (mut env, escrow_contract_address, token_contract_address, _, owner, recipient, _, _) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    let amount: u128 = token_utils::mint_amount;
    env.call_private(
        owner,
        Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient),
    );
}
