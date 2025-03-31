use uint253::uint253::{U253, MAX_U253};

use aztec::protocol_types::{
    constants::MAX_FIELD_VALUE,
    traits::{Deserialize, FromField, Packable, Serialize, ToField},
};

#[test]
fn test_multiplication_by_zero() {
    let zero = U253::zero();
    let onetwothree = U253::new(123);

    assert(zero * onetwothree == zero, "Zero value is not zero");
}

#[test(should_fail_with = "U253 multiplication overflow")]
fn test_multiplication_overflow() {
    let x = U253::new(7 * MAX_FIELD_VALUE / 50);
    let y = U253::new(23);
    // z = x * y = (7 * MAX / 50 ) * 23 = MAX * 161 / 50 > MAX --> overflows!
    // z = MAX * 161 / 50 mod MAX = MAX 11 / 50 > x = MAX 7 / 50
    let z = x * y;
}
