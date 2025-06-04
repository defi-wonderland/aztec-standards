use aztec::protocol_types::{
    constants::MAX_FIELD_VALUE,
    traits::{Deserialize, FromField, Packable, Serialize, ToField},
};
use std::cmp::{Eq, Ord, Ordering};
use std::ops::{Add, Div, Mul, Rem, Sub, Neg};
use bignum::{
    fields::bn254Fq::{BN254_Fq, BN254_Fq_PARAMS},
    bignum::{to_field, BigNum},
    fns::{
        expressions::evaluate_quadratic_expression, 
        unconstrained_ops::{__mul_with_quotient, __udiv_mod},
    },
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

    // Adds two Field values without overflow checks - use with caution
    pub fn add_unchecked(self, other: Self) -> Self {
        Self { value: self.value + other.value }
    }

    // Subtracts two Field values without underflow checks - use with caution
    pub fn sub_unchecked(self, other: Self) -> Self {
        Self { value: self.value - other.value }
    }

    // Multiplies two Field values without overflow checks - use with caution
    pub fn mul_unchecked(self, other: Self) -> Self {
        Self { value: self.value * other.value }
    }

    // Multiplies two Field values and uses BigNum's __udiv_mod to check for overflow.
    pub unconstrained fn mul_in_public(self, other: Self) -> Self {
        let result = Self { value: self.value * other.value };

        let self_bn: BN254_Fq = BN254_Fq::from(self.value);

        // let assert_remainder = BN254_Fq { limbs: result.__division_remainder(self) };
        let (q, remainder) = __udiv_mod(BN254_Fq::from(result.value).limbs, self_bn.limbs);
        assert(BN254_Fq { limbs: remainder } == BN254_Fq::zero(), "Field multiplication overflow");

        result
    }

    // Divides two Field values using BigNum's __udiv_mod instead of BigNum's div, which is suboptimal in public contetxt.
    pub unconstrained fn div_in_public(self, other: Self) -> Self {
        let self_bn: BN254_Fq = BN254_Fq::from(self.value);
        let other_bn: BN254_Fq = BN254_Fq::from(other.value);

        let (quotient, remainder) = __udiv_mod(self_bn.limbs, other_bn.limbs);
        Self { value: to_field(BN254_Fq { limbs: quotient }) }
    }

    pub unconstrained fn div_Field_by_128(self, other: Self) -> Self {
        let lo: u128 = (self.value & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) as u128;
        let hi: u128 = (self.value >> 128) as u128;
        let denom: u128 = other.value as u128;

        let mut quotient: u128 = 0;
        let mut r_hi = hi;
        let mut r_lo = lo;

        for i in 0..128 {
            let j = 128 - i - 1;
            let overflow_bit = (r_lo >> 127) & 1;
            r_lo = r_lo << 1;
            r_hi = (r_hi << 1) | overflow_bit;

            if r_hi >= denom {
                r_hi = r_hi - denom;
                quotient = quotient | (1 << j);
            }
        }

        Self { quotient as Field }
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
        // TODO: check if this assertion can be optimized by looking at parity. The result's parity changes when an overflow happens.
        assert(!result.lt(self.value), "Field addition overflow");
        Self { value: result }
    }
}

impl Sub for BigNumField {
    fn sub(self, other: Self) -> Self {
        // TODO: check if this assertion can be optimized by looking at parity. The result's parity changes when an underflow happens.
        assert(!self.value.lt(other.value), "Field subtraction underflow");
        let result = self.value - other.value;
        Self { value: result }
    }
}

impl Mul for BigNumField {
    fn mul(self, other: Self) -> Self {
        let self_bn: BN254_Fq = BN254_Fq::from(self.value);
        let other_bn: BN254_Fq = BN254_Fq::from(other.value);

        let (q, result) = unsafe { __mul_with_quotient(BN254_Fq_PARAMS, self_bn.limbs, other_bn.limbs) };
        if !std::runtime::is_unconstrained() {
            evaluate_quadratic_expression(
                BN254_Fq_PARAMS,
                [[self_bn.limbs]],
                [[false]],
                [[other_bn.limbs]],
                [[false]],
                [result],
                [true],
            );
        }
        assert(BN254_Fq { limbs: q } == BN254_Fq::zero(), "Field multiplication overflow");
        Self { value: to_field(BN254_Fq { limbs: result }) }
    }
}

impl Div for BigNumField {
    fn div(self, other: Self) -> Self {
        let self_bn: BN254_Fq = BN254_Fq::from(self.value);
        let other_bn: BN254_Fq = BN254_Fq::from(other.value);

        let result: BN254_Fq = self_bn / other_bn;
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
