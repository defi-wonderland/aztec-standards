use crate::test::utils;
use crate::types::account_note::AccountNote;

#[test]
unconstrained fn constructor_storage() {
    let (env, escrow_address, owner, recipient, escrow_secret) = utils::setup(/* with_account_contracts */ true);

    env.impersonate(escrow_address);
    let owner_note: AccountNote = utils::call_view_owner_note();

    assert(owner_note.owner == owner, "Incorrect owner");
    assert(owner_note.secret == escrow_secret, "Incorrect secret");
}