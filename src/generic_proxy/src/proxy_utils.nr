use crate::GenericProxy;
use aztec::{context::PrivateCall, protocol::address::AztecAddress};

// ---------------------------------------------------------------------------
// ViaProxy trait -- enables `call.via_proxy(proxy_address)` syntax
// ---------------------------------------------------------------------------
//
// Transforms a PrivateCall into a proxy-forwarded PrivateCall.
//
// The trait is parameterized by the output type R so that each arity impl
// can return the concrete PrivateCall type produced by the corresponding
// GenericProxy::forward_private_N function.
//
// ## Example
//
// ```noir
// use generic_proxy::proxy_utils::ViaProxy;
//
// let burn_call = Token::at(addr).burn_private(owner, amount, nonce);
// env.call_private(owner, burn_call.via_proxy(proxy_address));
// ```

pub trait ViaProxy<R> {
    fn via_proxy(self, proxy: AztecAddress) -> R;
}

// PrivateCall with 3 args (e.g., burn_private) -> forward_private_3
// forward_private_3 serializes (AztecAddress, FunctionSelector, [Field; 3]) = 5 fields
impl<let M: u32> ViaProxy<PrivateCall<17, 5, ()>> for PrivateCall<M, 3, ()> {
    fn via_proxy(self, proxy: AztecAddress) -> PrivateCall<17, 5, ()> {
        GenericProxy::at(proxy).forward_private_3(self.target_contract, self.selector, self.args)
    }
}
