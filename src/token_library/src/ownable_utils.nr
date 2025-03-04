pub mod OwnableLib {
    use aztec::{
        context::{PublicContext, PrivateContext},
        prelude::{AztecAddress, PublicMutable},
        protocol_types::abis::function_selector::FunctionSelector,
    };

    pub fn ownable_constructor(
        storage_owner: PublicMutable<AztecAddress, &mut PublicContext>,
        owner: AztecAddress,
    ) {
        storage_owner.write(owner);
    }

    /** ==========================================================
     * ======================= LIBRARIES =========================
     * ======================================================== */

    pub fn only_owner_private(
        context: &mut PrivateContext,
    ) {
        validate_owner_private(context, context.msg_sender());
    }

    pub fn validate_owner_private(
        context: &mut PrivateContext,
        caller: AztecAddress,
    ) {
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("validate_owner((Field))"),
            caller.serialize(),
        )
    }

    pub fn only_owner_public(
        context: &mut PublicContext,
        storage_owner: PublicMutable<AztecAddress, &mut PublicContext>,
    ) {
        validate_owner_public(context.msg_sender(), storage_owner);
    }

    pub fn validate_owner_public(
        caller: AztecAddress,
        storage_owner: PublicMutable<AztecAddress, &mut PublicContext>,
    ) {
        assert(caller == storage_owner.read(), "Only owner can call");
    }
}
