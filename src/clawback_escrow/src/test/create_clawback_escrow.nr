use crate::test::utils;

#[test]
unconstrained fn create_clawback_escrow() {
    let (env, clawback_escrow_contract_address, token_contract_address, owner, _) = utils::setup(
        /* with_account_contracts */ true,
        /* mint_amount */ U128::from_integer(1_000_000_000),
    );
}
