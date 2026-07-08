use crate::MultiToken;
use crate::test::utils;
use aztec::protocol::address::AztecAddress;
use compressed_string::FieldCompressedString;

#[test]
unconstrained fn constructor_stores_name_symbol_minter_auth() {
    // Deploy via constructor_with_minter and read back each stored field through its view.
    let (env, multitoken_contract_address, _, _, minter) = utils::setup_with_minter(false);

    let name = env.view_public(MultiToken::at(multitoken_contract_address).name());
    let expected_name = FieldCompressedString::from_string("TestMultiToken00000000000000000");
    assert(name == expected_name, "name is not set correctly");

    let symbol = env.view_public(MultiToken::at(multitoken_contract_address).symbol());
    let expected_symbol = FieldCompressedString::from_string("TMT0000000000000000000000000000");
    assert(symbol == expected_symbol, "symbol is not set correctly");

    let stored_minter = env.view_public(MultiToken::at(multitoken_contract_address).get_minter());
    assert(stored_minter == minter, "minter is not set correctly");

    // setup_with_minter wires auth_contract = zero (hook disabled by default).
    let stored_auth =
        env.view_public(MultiToken::at(multitoken_contract_address).get_auth_contract());
    assert(stored_auth == AztecAddress::zero(), "auth contract is not set correctly");
}

#[test]
unconstrained fn get_auth_contract_zero_when_disabled() {
    // With auth_contract = zero the hook is disabled-by-default; get_auth_contract returns zero.
    let (env, multitoken_contract_address, _, _, _) = utils::setup_with_minter(false);

    let stored_auth =
        env.view_public(MultiToken::at(multitoken_contract_address).get_auth_contract());
    assert(stored_auth == AztecAddress::zero(), "auth contract should be zero when disabled");
}
