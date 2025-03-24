// Copyright (c) 2025 Clarified Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

use aztec::protocol_types::traits::{Deserialize, FromField, Packable, Serialize, ToField};
use std::cmp::{Eq, Ord, Ordering};
use std::ops::{Add, Div, Mul, Rem, Sub};

// Maximum value for U253 (2^253 - 1), chosen to fit within Aztec's field arithmetic bounds
pub global MAX_U253: Field = 0x1fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

pub global U253_PACKED_LEN: u32 = 1;

pub struct U253 {
    pub(crate) value: Field,
}

impl U253 {
    pub fn new(value: Field) -> Self {
        value.assert_max_bit_size::<253>();
        Self { value }
    }

    pub fn new_unchecked(value: Field) -> Self {
        Self { value }
    }

    pub fn from_integer(value: Field) -> Self {
        value.assert_max_bit_size::<253>();
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
        Self { value: MAX_U253 }
    }

    pub fn is_zero(self) -> bool {
        self.value == 0
    }

    // Performs division with remainder using binary long division algorithm
    // Returns (quotient, remainder) tuple
    pub unconstrained fn div_rem_unconstrained(self, other: Self) -> (Self, Self) {
        assert(!(other.value == 0), "Division by zero");

        self.value.assert_max_bit_size::<253>();
        other.value.assert_max_bit_size::<253>();

        let bits: [u1; 253] = self.value.to_be_bits();
        let divisor = other.value;

        let mut quotient: Field = 0;
        let mut remainder: Field = 0;

        // Process each bit from MSB to LSB, similar to paper-and-pencil division
        for i in 0..253 {
            // Shift remainder left by 1 bit and add next bit
            remainder = remainder * 2 + (bits[i] as Field);

            // Single comparison to determine if we should subtract divisor
            // Changed to just !remainder.lt(divisor) which means remainder >= divisor
            if !remainder.lt(divisor) {
                remainder = remainder - divisor;
                quotient = quotient * 2 + 1;
            } else {
                quotient = quotient * 2;
            }
        }
        (Self { value: quotient }, Self { value: remainder })
    }

    // Constrains the results of a division operation
    // Ensures that remainder < divisor and quotient * divisor + remainder == dividend
    pub fn constrain_division_result(
        quotient: Self,
        remainder: Self,
        dividend: Self,
        divisor: Self,
    ) {
        // Critical constraint: remainder must be less than divisor
        assert(remainder.value.lt(divisor.value), "Remainder must be less than divisor");

        // Verify division property: dividend = quotient * divisor + remainder
        assert(
            quotient * divisor + remainder == dividend,
            "Unconstrained division result is incorrect",
        );
    }

    // Performs division with remainder using unconstrained binary long division algorithm, then
    // constrains the result via multiplicative properties
    // Returns (quotient, remainder) tuple
    pub fn div_rem(self, other: Self) -> (Self, Self) {
        assert(!(other.value == 0), "Division by zero");

        if self.value == other.value {
            (Self::one(), Self::zero())
        } else if self.is_zero() {
            (Self::zero(), Self::zero())
        } else if other.value == 1 {
            (self, Self::zero())
        } else if self.value.lt(other.value) {
            (Self::zero(), self)
        } else {
            /// Safety: constraining this immediately after with `constrain_division_result`
            let (quotient, remainder) = unsafe { self.div_rem_unconstrained(other) };

            // Constrain the division result
            Self::constrain_division_result(quotient, remainder, self, other);

            (quotient, remainder)
        }
    }

    // Adds two U253 values without overflow checks - use with caution
    pub fn add_unchecked(self, other: Self) -> Self {
        Self { value: self.value + other.value }
    }

    // Subtracts two U253 values without underflow checks - use with caution
    pub fn sub_unchecked(self, other: Self) -> Self {
        Self { value: self.value - other.value }
    }
}

impl ToField for U253 {
    fn to_field(self) -> Field {
        self.value
    }
}

impl FromField for U253 {
    fn from_field(value: Field) -> Self {
        value.assert_max_bit_size::<253>();
        Self { value }
    }
}

impl Serialize<1> for U253 {
    fn serialize(self) -> [Field; 1] {
        [self.value]
    }
}

impl Deserialize<1> for U253 {
    fn deserialize(fields: [Field; 1]) -> Self {
        fields[0].assert_max_bit_size::<253>();
        assert(fields[0].lt(MAX_U253 + 1), "Deserialized value is too large");
        Self { value: fields[0] }
    }
}

impl Add for U253 {
    fn add(self, other: Self) -> Self {
        let result = self.value + other.value;
        result.assert_max_bit_size::<253>();

        assert(!MAX_U253.lt(result), "U253 addition overflow");
        assert(!result.lt(self.value), "U253 addition overflow");
        assert(!result.lt(other.value), "U253 addition overflow");
        Self { value: result }
    }
}

impl Sub for U253 {
    fn sub(self, other: Self) -> Self {
        assert(
            other.value.lt(self.value) | other.value.eq(self.value),
            "U253 subtraction underflow",
        );
        let result = self.value - other.value;
        result.assert_max_bit_size::<253>();
        Self { value: result }
    }
}

impl Mul for U253 {
    fn mul(self, other: Self) -> Self {
        let result = self.value * other.value;

        result.assert_max_bit_size::<253>();
        // Allow multiplication by 1 without additional checks, otherwise check for overflow
        assert(
            (self.value == 1)
                | (other.value == 1)
                | (result.lt(MAX_U253 + 1) & !result.lt(self.value) & !result.lt(other.value)),
            "U253 multiplication overflow",
        );
        Self { value: result }
    }
}

impl Div for U253 {
    fn div(self, other: Self) -> Self {
        let (quotient, _) = self.div_rem(other);
        quotient
    }
}

impl Rem for U253 {
    fn rem(self, other: Self) -> Self {
        let (_, remainder) = self.div_rem(other);
        remainder
    }
}

impl Ord for U253 {
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

impl Eq for U253 {
    fn eq(self, other: Self) -> bool {
        self.value.eq(other.value)
    }
}

impl Packable<U253_PACKED_LEN> for U253 {
    fn pack(self) -> [Field; U253_PACKED_LEN] {
        [self.value]
    }

    fn unpack(fields: [Field; U253_PACKED_LEN]) -> Self {
        U253::from_integer(fields[0])
    }
}
