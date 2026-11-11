//! Ruby-free kernels of the Avro binary encoding, kept apart from the extension so `cargo test` needs no libruby.

pub mod decimal;

/// Appends `n` as an Avro `long` (and `int`): zigzag, then a little-endian base-128 varint.
pub fn write_long(n: i64, out: &mut Vec<u8>) {
    let mut z = ((n << 1) ^ (n >> 63)) as u64;
    while z >= 0x80 {
        out.push((z as u8) | 0x80);
        z >>= 7;
    }
    out.push(z as u8);
}

/// Appends a length-prefixed byte run: Avro `bytes`, and `string` once it is UTF-8.
pub fn write_bytes(bytes: &[u8], out: &mut Vec<u8>) {
    write_long(bytes.len() as i64, out);
    out.extend_from_slice(bytes);
}

#[cfg(test)]
mod tests {
    use super::{write_bytes, write_long};

    fn long(n: i64) -> Vec<u8> {
        let mut out = Vec::new();
        write_long(n, &mut out);
        out
    }

    #[test]
    fn zigzag_varints() {
        assert_eq!(long(0), [0]);
        assert_eq!(long(-1), [1]);
        assert_eq!(long(1), [2]);
        assert_eq!(long(-64), [127]);
        assert_eq!(long(64), [128, 1]);
        assert_eq!(long(i64::MAX), [254, 255, 255, 255, 255, 255, 255, 255, 255, 1]);
        assert_eq!(long(i64::MIN), [255, 255, 255, 255, 255, 255, 255, 255, 255, 1]);
    }

    #[test]
    fn byte_runs() {
        let mut out = Vec::new();
        write_bytes(b"ab", &mut out);
        assert_eq!(out, [4, b'a', b'b']);
    }
}
