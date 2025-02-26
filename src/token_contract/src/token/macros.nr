mod transferrable;
mod mintable;

pub comptime fn token(m: Module) -> Quoted {
    let token_body = transferrable::TRANSFERRABLE_CODE;
    let mintable_body = mintable::MINTABLE_CODE;

    quote {
        $token_body
        $mintable_body
    }
}
