//! The unscaled integer of a decimal, from `BigDecimal#to_s` text (`"-0.12345e3"`), as minimal big-endian
//! two's-complement bytes: the Avro `decimal` logical type on `bytes`.

/// The most unscaled digits handled; anything longer goes to the pure path.
const MAX_DIGITS: i64 = 1_000;

#[derive(Debug, PartialEq, Eq)]
pub struct Unscaled {
    negative: bool,
    /// Little-endian base 2**32 limbs of the magnitude; empty is zero.
    limbs: Vec<u32>,
}

impl Unscaled {
    /// `None` when the text is not a finite decimal, for zero at scale 0, when scaling by `scale` would need rounding, or when the
    /// unscaled value has more than `precision` digits (the cases the avro gem raises on).
    pub fn parse(text: &[u8], scale: u32, precision: u32) -> Option<Self> {
        let (negative, rest) = match text.split_first() {
            Some((b'-', rest)) => (true, rest),
            _ => (false, text),
        };
        let rest = rest.strip_prefix(b"0.")?;
        let (digits, exponent) = match rest.iter().position(|&b| b == b'e') {
            Some(i) => (&rest[..i], parse_exponent(&rest[i + 1..])?),
            None => (rest, 0),
        };
        if digits.is_empty() || !digits.iter().all(u8::is_ascii_digit) {
            return None;
        }
        let digits = match digits.iter().rposition(|&b| b != b'0') {
            Some(last) => &digits[..=last],
            // The avro gem 1.12 raises "Rounding necessary" for a zero at scale 0 (observed); it writes zero at any
            // other scale.
            None if scale == 0 => return None,
            None => return Some(Unscaled { negative: false, limbs: Vec::new() }),
        };
        let first = digits.iter().position(|&b| b != b'0')?;
        let digits = &digits[first..];
        // value = 0.<digits> * 10**exponent = digits * 10**(exponent - len); leading zeros after "0." shift the point.
        let len = digits.len() as i64 + first as i64;
        let shift = exponent.checked_sub(len)?.checked_add(scale as i64)?;
        if shift < 0 {
            return None;
        }
        let total = digits.len() as i64 + shift;
        if total > precision as i64 || total > MAX_DIGITS {
            return None;
        }
        let mut limbs = Vec::with_capacity((total as usize) / 9 + 1);
        for &d in digits {
            mul_add(&mut limbs, 10, (d - b'0') as u32);
        }
        for _ in 0..shift {
            mul_add(&mut limbs, 10, 0);
        }
        Some(Unscaled { negative, limbs })
    }

    pub fn twos_complement(&self) -> Vec<u8> {
        let mut bytes: Vec<u8> = self.limbs.iter().rev().flat_map(|limb| limb.to_be_bytes()).collect();
        let lead = bytes.iter().position(|&b| b != 0).unwrap_or(bytes.len());
        bytes.drain(..lead);
        if bytes.is_empty() {
            return vec![0];
        }
        if !self.negative {
            if bytes[0] & 0x80 != 0 {
                bytes.insert(0, 0);
            }
            return bytes;
        }
        for b in bytes.iter_mut() {
            *b = !*b;
        }
        for b in bytes.iter_mut().rev() {
            let (sum, carry) = b.overflowing_add(1);
            *b = sum;
            if !carry {
                break;
            }
        }
        if bytes[0] & 0x80 == 0 {
            bytes.insert(0, 0xff);
        }
        bytes
    }
}

fn parse_exponent(text: &[u8]) -> Option<i64> {
    let s = std::str::from_utf8(text).ok()?;
    let s = s.strip_prefix('+').unwrap_or(s);
    s.parse::<i64>().ok()
}

fn mul_add(limbs: &mut Vec<u32>, mul: u32, add: u32) {
    let mut carry = add as u64;
    for limb in limbs.iter_mut() {
        let v = (*limb as u64) * (mul as u64) + carry;
        *limb = v as u32;
        carry = v >> 32;
    }
    if carry > 0 {
        limbs.push(carry as u32);
    }
}

#[cfg(test)]
mod tests {
    use super::Unscaled;

    fn bytes(text: &str, scale: u32, precision: u32) -> Option<Vec<u8>> {
        Unscaled::parse(text.as_bytes(), scale, precision).map(|u| u.twos_complement())
    }

    #[test]
    fn small_values() {
        assert_eq!(bytes("0.0", 2, 10), Some(vec![0]));
        assert_eq!(bytes("-0.0", 2, 10), Some(vec![0]));
        assert_eq!(bytes("0.0", 0, 10), None);
        assert_eq!(bytes("0.1e1", 2, 10), Some(vec![100]));
        assert_eq!(bytes("-0.1e1", 2, 10), Some(vec![156]));
        assert_eq!(bytes("0.127e1", 2, 10), Some(vec![127]));
        assert_eq!(bytes("0.128e1", 2, 10), Some(vec![0, 128]));
        assert_eq!(bytes("-0.128e1", 2, 10), Some(vec![128]));
        assert_eq!(bytes("-0.129e1", 2, 10), Some(vec![255, 127]));
        assert_eq!(bytes("-0.1e-1", 2, 10), Some(vec![255]));
        assert_eq!(bytes("0.1e6", 2, 10), Some(vec![0, 152, 150, 128]));
    }

    #[test]
    fn rounding_and_precision() {
        assert_eq!(bytes("0.1234e1", 2, 10), None);
        assert_eq!(bytes("0.1e3", 2, 4), None);
        assert_eq!(bytes("0.9999e2", 2, 4), Some(vec![39, 15]));
        assert_eq!(bytes("NaN", 2, 4), None);
        assert_eq!(bytes("Infinity", 2, 4), None);
        assert_eq!(bytes("-Infinity", 2, 4), None);
    }

    #[test]
    fn wide_values() {
        let nines = format!("0.{}e40", "9".repeat(40));
        let expected = vec![29, 99, 41, 241, 195, 92, 164, 191, 171, 185, 245, 96, 255, 255, 255, 255, 255];
        assert_eq!(bytes(&nines, 0, 40), Some(expected));
        let limit = "0.170141183460469231731687303715884105728e39";
        let mut expected = vec![0, 128];
        expected.extend(std::iter::repeat_n(0, 15));
        assert_eq!(bytes(limit, 0, 40), Some(expected));
    }
}
