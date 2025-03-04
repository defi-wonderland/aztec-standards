pub mod HookLib {
    use aztec::{context::{PrivateContext, PublicContext}, prelude::AztecAddress};

    pub fn before_private_transfer<T>(_context: &mut PrivateContext, _storage: T, _from: AztecAddress, _to: AztecAddress, amount: U128) -> U128 {
        amount
    }

    pub fn before_public_transfer<T>(_context: &mut PublicContext, _storage: T, _from: AztecAddress, _to: AztecAddress, amount: U128) -> U128 {
        amount
    }
}
