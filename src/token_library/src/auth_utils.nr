pub mod AuthLib {
    use authwit::auth::{
        assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
    };
    use aztec::{context::{PrivateContext, PublicContext}, prelude::AztecAddress};

    pub fn validate_from_private(context: &mut PrivateContext,from: AztecAddress, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }

    pub fn validate_from_public(context: &mut PublicContext, from: AztecAddress, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            // TODO(#34): uncomment assert_current_call_valid_authwit_public
            // assert_current_call_valid_authwit_public(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
    }
}
