pub mod HookLib {
    use aztec::{
        context::{PrivateContext, PublicContext},
        prelude::AztecAddress,
        protocol_types::abis::function_selector::FunctionSelector,
    };

    pub fn before_private_transfer(
        context: &mut PrivateContext,
        from: AztecAddress,
        _: AztecAddress,
        amount: U128,
    ) {
        context.call_private_function(
            context.this_address(),
            FunctionSelector::from_signature("_authorize_in_private((Field),(Field,Field))"),
            serialize_authorize_in_private_call(from, amount.serialize()),
        );
    }

    pub fn before_public_transfer(
        context: &mut PublicContext,
        from: AztecAddress,
        to: AztecAddress,
        amount: U128,
    ) {}

    fn serialize_authorize_in_private_call(from: AztecAddress, amount: [Field; 2]) -> [Field; 3] {
        let mut result = [0 as Field; 3];
        result[0] = from.to_field();
        result[1] = amount[0];
        result[2] = amount[1];
        result
    }
}
