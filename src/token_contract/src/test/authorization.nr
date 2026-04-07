use crate::test::utils::{self, mint_amount};
use crate::Token;
use aztec::oracle::random::random;
use std::test::OracleMock;

// --------- View Function ---------

#[test]
unconstrained fn get_auth_contract_returns_configured_address() {
    let (env, token_contract_address, _, _, auth_contract_address) =
        utils::setup_with_initial_supply_and_auth(false, mint_amount);

    let stored_auth = env.view_public(Token::at(token_contract_address).get_auth_contract());
    assert(stored_auth == auth_contract_address, "Auth contract address mismatch");
}

#[test]
unconstrained fn get_auth_contract_returns_zero_when_disabled() {
    let (env, token_contract_address, _, _) = utils::setup_and_mint_to_public_without_minter(false);

    let stored_auth = env.view_public(Token::at(token_contract_address).get_auth_contract());
    assert(
        stored_auth == aztec::protocol::address::AztecAddress::zero(),
        "Auth contract should be zero",
    );
}

// --------- Private Transfers with Auth ---------

#[test]
unconstrained fn auth_transfer_private_to_private() {
    let (mut env, token_contract_address, owner, recipient, _auth) =
        utils::setup_with_initial_supply_and_auth(false, mint_amount);

    // Move to private first
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_public_to_private(owner, owner, mint_amount, 0),
    );

    let transfer_amount = mint_amount / 10;
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_private(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    utils::check_private_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_private_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn auth_transfer_private_to_public() {
    let (mut env, token_contract_address, owner, recipient, _auth) =
        utils::setup_with_initial_supply_and_auth(false, mint_amount);

    // Move to private first
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_public_to_private(owner, owner, mint_amount, 0),
    );

    let transfer_amount = mint_amount / 10;
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_public(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    utils::check_private_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_public_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn auth_transfer_private_to_public_with_commitment() {
    let (mut env, token_contract_address, owner, recipient, _auth) =
        utils::setup_with_initial_supply_and_auth(false, mint_amount);

    // Move to private first
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_public_to_private(owner, owner, mint_amount, 0),
    );

    let transfer_amount = mint_amount / 10;
    let _commitment = env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    utils::check_private_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_public_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn auth_transfer_private_to_commitment() {
    let (mut env, token_contract_address, owner, recipient, _auth) =
        utils::setup_with_initial_supply_and_auth(false, mint_amount);

    // Move to private first
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_public_to_private(owner, owner, mint_amount, 0),
    );

    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    let transfer_amount = mint_amount / 10;
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_private_to_commitment(
            owner,
            commitment,
            transfer_amount,
            0,
        ),
    );

    utils::check_private_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_private_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn auth_transfer_public_to_private() {
    let (mut env, token_contract_address, owner, recipient, _auth) =
        utils::setup_with_initial_supply_and_auth(false, mint_amount);

    let transfer_amount = mint_amount / 10;
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_public_to_private(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    utils::check_public_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_private_balance(env, token_contract_address, recipient, transfer_amount);
}

// --------- Public Transfers with Auth ---------

#[test]
unconstrained fn auth_transfer_public_to_public() {
    let (mut env, token_contract_address, owner, recipient, _auth) =
        utils::setup_with_initial_supply_and_auth(false, mint_amount);

    let transfer_amount = mint_amount / 10;
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_public(
            owner,
            recipient,
            transfer_amount,
            0,
        ),
    );

    utils::check_public_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - transfer_amount,
    );
    utils::check_public_balance(env, token_contract_address, recipient, transfer_amount);
}

#[test]
unconstrained fn auth_transfer_public_to_commitment() {
    let (mut env, token_contract_address, owner, recipient, _auth) =
        utils::setup_with_initial_supply_and_auth(false, mint_amount);

    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    let commitment = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_commitment(
            owner,
            commitment,
            mint_amount,
            0,
        ),
    );

    utils::check_private_balance(env, token_contract_address, recipient, mint_amount);
}

// --------- Minting with Auth ---------

#[test]
unconstrained fn auth_mint_to_private() {
    let (mut env, token_contract_address, _, recipient, minter, _auth) =
        utils::setup_with_minter_and_auth(false);

    let amount: u128 = 10_000;
    utils::mint_to_private(env, token_contract_address, recipient, amount, minter);

    utils::check_private_balance(env, token_contract_address, recipient, amount);
    utils::check_total_supply(env, token_contract_address, amount);
}

#[test]
unconstrained fn auth_mint_to_public() {
    let (mut env, token_contract_address, owner, _, minter, _auth) =
        utils::setup_with_minter_and_auth(false);

    let amount: u128 = 10_000;
    env.call_public(minter, Token::at(token_contract_address).mint_to_public(owner, amount));

    utils::check_public_balance(env, token_contract_address, owner, amount);
    utils::check_total_supply(env, token_contract_address, amount);
}

#[test]
unconstrained fn auth_mint_to_commitment() {
    let (mut env, token_contract_address, _, recipient, minter, _auth) =
        utils::setup_with_minter_and_auth(false);

    let commitment = env.call_private(
        minter,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, minter),
    );

    let amount: u128 = 10_000;
    env.call_public(minter, Token::at(token_contract_address).mint_to_commitment(commitment, amount));

    utils::check_private_balance(env, token_contract_address, recipient, amount);
    utils::check_total_supply(env, token_contract_address, amount);
}

// --------- Burning with Auth ---------

#[test]
unconstrained fn auth_burn_private() {
    let (mut env, token_contract_address, owner, _, _auth) =
        utils::setup_with_initial_supply_and_auth(false, mint_amount);

    // Move to private first
    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_public_to_private(owner, owner, mint_amount, 0),
    );

    let burn_amount = mint_amount / 10;
    env.call_private(owner, Token::at(token_contract_address).burn_private(owner, burn_amount, 0));

    utils::check_private_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - burn_amount,
    );
    utils::check_total_supply(env, token_contract_address, mint_amount - burn_amount);
}

#[test]
unconstrained fn auth_burn_public() {
    let (mut env, token_contract_address, owner, _, _auth) =
        utils::setup_with_initial_supply_and_auth(false, mint_amount);

    let burn_amount = mint_amount / 10;
    env.call_public(owner, Token::at(token_contract_address).burn_public(owner, burn_amount, 0));

    utils::check_public_balance(
        env,
        token_contract_address,
        owner,
        mint_amount - burn_amount,
    );
    utils::check_total_supply(env, token_contract_address, mint_amount - burn_amount);
}
