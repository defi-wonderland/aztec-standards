pub mod HookLib {
    use aztec::{context::{PrivateContext, PublicContext}, prelude::AztecAddress};

    pub fn before_private_transfer(context: &mut PrivateContext, from: AztecAddress, to: AztecAddress, amount: U128) {}

    pub fn before_public_transfer(context: &mut PublicContext, from: AztecAddress, to: AztecAddress, amount: U128) {}
}
