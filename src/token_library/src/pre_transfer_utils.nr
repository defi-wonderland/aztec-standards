pub mod PreTransferLib {
    use aztec::{context::{PrivateContext, PublicContext}, prelude::AztecAddress};

    pub fn before_private_transfer<T>(_context: &mut PrivateContext, _storage: T, _from: AztecAddress, _to: AztecAddress, _amount: U128) {}

    pub fn before_public_transfer<T>(_context: &mut PublicContext, _storage: T, _from: AztecAddress, _to: AztecAddress, _amount: U128) {}
}
