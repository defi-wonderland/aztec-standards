use aztec::macros::aztec;

#[aztec]
pub contract MultiToken {
    use aztec::macros::functions::{external, initializer};

    #[external("public")]
    #[initializer]
    fn constructor() {}
}
