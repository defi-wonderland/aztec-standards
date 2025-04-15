use aztec::protocol_types::{
    constants::MAX_FIELD_VALUE,
    traits::{Deserialize, FromField, Packable, Serialize, ToField},
};
use std::cmp::{Eq, Ord, Ordering};
use std::ops::{Add, Div, Mul, Rem, Sub, Neg};
use bignum::{
    fields::bn254Fq::{BN254_Fq, BN254_Fq_Params},
    bignum::to_field,
    BigNum,
    BigNumTrait,
};

pub struct BigNumField {
    pub(crate) value: Field,
}

impl BigNumField {
    pub fn new(value: Field) -> Self {
        Self { value }
    }

    pub fn from_integer(value: Field) -> Self {
        Self { value }
    }

    pub fn to_integer(self) -> Field {
        self.value
    }

    pub fn zero() -> Self {
        Self { value: 0 }
    }

    pub fn one() -> Self {
        Self { value: 1 }
    }

    pub fn max() -> Self {
        Self { value: MAX_FIELD_VALUE }
    }

    pub fn is_zero(self) -> bool {
        self.value == 0
    }

    // Multiplies two Field values without overflow checks - use with caution
    pub fn mul_unchecked(self, other: Self) -> Self {
        Self { value: self.value * other.value }
    }

    // Adds two Field values without overflow checks - use with caution
    pub fn add_unchecked(self, other: Self) -> Self {
        Self { value: self.value + other.value }
    }

    // Subtracts two Field values without underflow checks - use with caution
    pub fn sub_unchecked(self, other: Self) -> Self {
        Self { value: self.value - other.value }
    }
}

impl ToField for BigNumField {
    fn to_field(self) -> Field {
        self.value
    }
}

impl FromField for BigNumField {
    fn from_field(value: Field) -> Self {
        Self { value }
    }
}

impl Serialize<1> for BigNumField {
    fn serialize(self) -> [Field; 1] {
        [self.value]
    }
}

impl Deserialize<1> for BigNumField {
    fn deserialize(fields: [Field; 1]) -> Self {
        Self { value: fields[0] }
    }
}

impl Add for BigNumField {
    fn add(self, other: Self) -> Self {
        // No need to use BigNum limbs
        let result = self.value + other.value;
        assert(!result.lt(self.value), "Field addition overflow");
        Self { value: result }
    }
}

impl Sub for BigNumField {
    fn sub(self, other: Self) -> Self {
        // No need to use BigNum limbs
        assert(!self.value.lt(other.value), "Field subtraction underflow");
        let result = self.value - other.value;
        Self { value: result }
    }
}

impl Mul for BigNumField {
    fn mul(self, other: Self) -> Self {
        let self_bn: BN254_Fq = BN254_Fq::from(self.value);
        let other_bn: BN254_Fq = BN254_Fq::from(other.value);

        let result: BN254_Fq = self_bn * other_bn;
        assert(result.div(self_bn) == other_bn, "U256 multiplication overflow");
        Self { value: to_field(result) }
    }
}

impl Div for BigNumField {
    fn div(self, other: Self) -> Self {
        let result: BN254_Fq = BN254_Fq::from(self.value) / BN254_Fq::from(other.value);
        Self { value: to_field(result) }
    }
}

impl Ord for BigNumField {
    fn cmp(self, other: Self) -> Ordering {
        if self.value.lt(other.value) {
            Ordering::less()
        } else if self.value.eq(other.value) {
            Ordering::equal()
        } else {
            Ordering::greater()
        }
    }
}

impl Eq for BigNumField {
    fn eq(self, other: Self) -> bool {
        self.value == other.value
    }
}

impl Packable<1> for BigNumField {
    fn pack(self) -> [Field; 1] {
        [self.value]
    }

    fn unpack(fields: [Field; 1]) -> Self {
        Self { value: fields[0] }
    }
}
