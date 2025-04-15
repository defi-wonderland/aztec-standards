use aztec::protocol_types::{
    traits::{Deserialize, FromField, Packable, Serialize, ToField},
};
use std::cmp::{Eq, Ord, Ordering};
use std::ops::{Add, Div, Mul, Sub};
use bignum::{
    fields::U256::U256,
    bignum::to_field,
    bignum::BigNumTrait,
};

pub struct BigNumField {
    pub(crate) limbs: [Field; 3],
}

impl BigNumField {
    pub fn new(value: Field) -> Self {
        let value256 = U256::from(value);
        Self { limbs: [value256.limbs[0] as Field, value256.limbs[1] as Field, value256.limbs[2] as Field] }
    }

    pub fn zero() -> Self {
        Self { limbs: [0,0,0] }
    }

    pub fn one() -> Self {
        Self { limbs: [1,0,0] }
    }

    pub fn max() -> Self {
        // [0xffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffff, 0xffff]
        Self { limbs: [1329227995784915872903807060280344575, 1329227995784915872903807060280344575, 65535] }
    }

    pub fn is_zero(self) -> bool {
        U256::from_slice([self.limbs[0] as u128, self.limbs[1] as u128, self.limbs[2] as u128]) == U256::zero()
    }

    // Multiplies two Field values without overflow checks - use with caution
    // pub fn mul_unchecked(self, other: Self) -> Self {
    //     Self { value: self.value * other.value }
    // }

    // // Adds two Field values without overflow checks - use with caution
    // pub fn add_unchecked(self, other: Self) -> Self {
    //     Self { value: self.value + other.value }
    // }

    // // Subtracts two Field values without underflow checks - use with caution
    // pub fn sub_unchecked(self, other: Self) -> Self {
    //     Self { value: self.value - other.value }
    // }
}

impl ToField for BigNumField {
    fn to_field(self) -> Field {
        to_field(U256::from_slice([self.limbs[0] as u128, self.limbs[1] as u128, self.limbs[2] as u128]))
    }
}

impl FromField for BigNumField {
    fn from_field(value: Field) -> Self {
        let value256 = U256::from(value);
        Self { limbs: [value256.limbs[0] as Field, value256.limbs[1] as Field, value256.limbs[2] as Field] }    }
}

impl Serialize<3> for BigNumField {
    fn serialize(self) -> [Field; 3] {
        [self.limbs[0] as Field, self.limbs[1] as Field, self.limbs[2] as Field]
    }
}

impl Deserialize<3> for BigNumField {
    fn deserialize(fields: [Field; 3]) -> BigNumField {
        Self { limbs: [fields[0], fields[1], fields[2]] }
    }
}

impl Add for BigNumField {
    fn add(self, other: Self) -> Self {
        let result: U256 = U256::from_slice([self.limbs[0] as u128, self.limbs[1] as u128, self.limbs[2] as u128]) + U256::from_slice([other.limbs[0] as u128, other.limbs[1] as u128, other.limbs[2] as u128]);
        Self { limbs: [result.limbs[0] as Field, result.limbs[1] as Field, result.limbs[2] as Field] }    
    }
}

impl Sub for BigNumField {
    fn sub(self, other: Self) -> Self {
        let result: U256 = U256::from_slice([self.limbs[0] as u128, self.limbs[1] as u128, self.limbs[2] as u128]) - U256::from_slice([other.limbs[0] as u128, other.limbs[1] as u128, other.limbs[2] as u128]);
        Self { limbs: [result.limbs[0] as Field, result.limbs[1] as Field, result.limbs[2] as Field] }  
    }
}

impl Mul for BigNumField {
    fn mul(self, other: Self) -> Self {
        let result: U256 = U256::from_slice([self.limbs[0] as u128, self.limbs[1] as u128, self.limbs[2] as u128]) * U256::from_slice([other.limbs[0] as u128, other.limbs[1] as u128, other.limbs[2] as u128]);
        Self { limbs: [result.limbs[0] as Field, result.limbs[1] as Field, result.limbs[2] as Field] }  
    }
}

impl Div for BigNumField {
    fn div(self, other: Self) -> Self {
        let result: U256 = U256::from_slice([self.limbs[0] as u128, self.limbs[1] as u128, self.limbs[2] as u128]).udiv(U256::from_slice([other.limbs[0] as u128, other.limbs[1] as u128, other.limbs[2] as u128]));
        Self { limbs: [result.limbs[0] as Field, result.limbs[1] as Field, result.limbs[2] as Field] }  
    }
}

impl Ord for BigNumField {
    fn cmp(self, other: Self) -> Ordering {
        let bn_self = U256::from_slice([self.limbs[0] as u128, self.limbs[1] as u128, self.limbs[2] as u128]);
        let bn_other = U256::from_slice([other.limbs[0] as u128, other.limbs[1] as u128, other.limbs[2] as u128]);

        if bn_self < bn_other {
            Ordering::less()
        } else if bn_self.eq(bn_other) {
            Ordering::equal()
        } else {
            Ordering::greater()
        }
    }
}

impl Eq for BigNumField {
    fn eq(self, other: Self) -> bool {
        U256::from_slice([self.limbs[0] as u128, self.limbs[1] as u128, self.limbs[2] as u128]) == U256::from_slice([other.limbs[0] as u128, other.limbs[1] as u128, other.limbs[2] as u128])
    }
}

impl Packable<3> for BigNumField {
    fn pack(self) -> [Field; 3] {
        [self.limbs[0] as Field, self.limbs[1] as Field, self.limbs[2] as Field]
    }

    fn unpack(fields: [Field; 3]) -> Self {
        Self { limbs: [fields[0], fields[1], fields[2]] }
    }
}
