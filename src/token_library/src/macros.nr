mod transferrable;
mod mintable;

use aztec::prelude::{AztecAddress, PublicMutable};

pub comptime fn token<Context>(m: Module) {
    let token_body = transferrable::TRANSFERRABLE_CODE;
    let mintable_body = mintable::MINTABLE_CODE;

    m.add_item(token_body);
    m.add_item(mintable_body);

    let storage_struct = m.structs().filter(|s| s.name() == quote { Storage })[0];
    let current_fields = storage_struct.fields_as_written();
    // TODO add this field to the array
    let new_fields = current_fields.push_back((quote { new_field }, quote { PublicMutable<U128, Context> }.as_type()));
    storage_struct.set_fields(new_fields);

    assert(is_azrc20(m), "Token must implement AzRC-20");
}


comptime fn is_azrc20(m: Module) -> bool {
    let f = m.functions().filter(|f| f.name() == quote { transfer_public_to_public });
    let params = f[0].parameters();
    
    f.len() > 0 
        & f[0].has_named_attribute("public")
        & (params[0] == (quote { from }, quote{ AztecAddress }.as_type()))
        & (params[1] == (quote { to }, quote{ AztecAddress }.as_type()))
        & (params[2] == (quote { amount }, quote{ U128 }.as_type()))
        & (f[0].return_type() == quote {()}.as_type()) // void return
}