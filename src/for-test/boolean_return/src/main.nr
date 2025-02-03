use dep::aztec::macros::aztec;

#[aztec]
// Mocked boolean return contract for tests
pub contract BooleanReturn {
    use dep::aztec::{
        macros::{functions::{initializer, private, public, view}, storage::storage},
        prelude::PublicImmutable,
    };

    #[storage]
    struct Storage<Context> {
        return_value: PublicImmutable<bool, Context>,
    }

    #[public]
    #[initializer]
    fn constructor(return_value: bool) {
        storage.return_value.initialize(return_value);
    }

    #[view]
    #[private]
    fn get_boolean_in_private() -> bool {
        storage.return_value.read()
    }

    #[view]
    #[public]
    fn get_boolean_in_public() -> bool {
        storage.return_value.read()
    }
}
