mod transferrable;
mod mintable;
mod ownable;

pub comptime fn token(m: Module) -> Quoted {
    let token_body = transferrable::TRANSFERRABLE_CODE;
    let mintable_body = mintable::MINTABLE_CODE;
    let ownable_body = ownable::OWNABLE_CODE;

    quote {
        $token_body
        $mintable_body
        $ownable_body
    }
}
