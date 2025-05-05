pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract MulDiv {
    // aztec library
    use aztec::{
        context::PrivateContext,
        macros::{
            functions::{initializer, internal, private, public, utility, view},
            storage::storage,
        },
        prelude::{AztecAddress, Map, PublicContext, PublicImmutable, PublicMutable},
    };
    // encryption library
    use aztec::messages::logs::note::encode_and_encrypt_note;
    // balance library
    use balance_set::balance_set::BalanceSet;

    use bignum_field::bignum_field::BigNumField;

    /// @param private_balances The private balances of the token
    /// @param public_balances The public balances of the token
    #[storage]
    struct Storage<Context> {
        private_results: Map<AztecAddress, BalanceSet<Context>, Context>,
        public_results: PublicMutable<BigNumField, Context>,
    }

    /// @notice Initializes the contract
    #[public]
    #[initializer]
    fn constructor() {}

    /// @notice Transfer tokens from private balance to public balance
    /// @param x The address of the sender
    /// @param y The address of the recipient
    /// @param z The amount of tokens to transfer
    #[private]
    fn mul_div_in_private(x: BigNumField, y: BigNumField, z: BigNumField) {
        let account = context.msg_sender();
        let result = x.mul_unchecked(y) / z;

        storage.private_results.at(account).add(account, result).emit(encode_and_encrypt_note(&mut context, account, account));
    }

    /// @notice Transfer tokens from private balance to public balance
    /// @param x The address of the sender
    /// @param y The address of the recipient
    /// @param z The amount of tokens to transfer
    #[public]
    fn mul_div_in_public(x: BigNumField, y: BigNumField, z: BigNumField) {
        let result = x.mul_unchecked(y); // / z;

        let new_balance = storage.public_results.read() + result;
        storage.public_results.write(new_balance);
    }

    // /// @notice Transfer tokens from private balance to public balance
    // /// @param x The address of the sender
    // /// @param y The address of the recipient
    // #[public]
    // fn only_div_in_public(x: BigNumField, y: BigNumField) {
    //     let result = x / y;

    //     storage.public_results.write(result);
    // }

    // /// @notice Transfer tokens from private balance to public balance
    // /// @param x The address of the sender
    // /// @param y The address of the recipient
    // #[private]
    // fn only_div_in_private(x: BigNumField, y: BigNumField) {
    //     let account = context.msg_sender();
    //     let result = x / y;

    //     storage.private_results.at(account).add(account, result).emit(encode_and_encrypt_note(&mut context, account, account));
    // }
}
