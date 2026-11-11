//! Walks a Ruby datum against a plan and appends the Avro binary encoding to a buffer.
//!
//! Every failure is one of two kinds. `Mismatch`: the avro gem's validator certainly rejects this value for this
//! schema, so inside a union the next member can be tried. `Unsure`: anything else (a value this encoder does not
//! handle, or one whose outcome in the pure path it cannot predict); the whole encode is abandoned and the Ruby side
//! runs the pure path.

use magnus::{
    encoding::{Coderange, EncodingCapable, Index},
    prelude::*,
    r_hash::ForEach,
    rb_sys::AsRawValue,
    value::{Lazy, ReprValue},
    Float, Integer, RArray, RClass, RHash, RString, Ruby, Symbol, Value,
};

use field_struct_avro_kernel::{decimal, write_bytes, write_long};
use crate::plan::{Node, Plan};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Fail {
    Mismatch,
    Unsure,
}

type Step = Result<(), Fail>;

static BIG_DECIMAL: Lazy<RClass> = Lazy::new(|ruby| class_named(ruby, "BigDecimal"));
static DATE: Lazy<RClass> = Lazy::new(|ruby| class_named(ruby, "Date"));

fn class_named(ruby: &Ruby, name: &str) -> RClass {
    ruby.class_object()
        .const_get::<_, RClass>(name)
        .unwrap_or_else(|_| panic!("{name} must be loaded before FieldStruct::Avro::Native"))
}

/// The shape of a Ruby value, as far as the encoder cares. Only exact classes count; subclasses are `Other`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Kind {
    Nil,
    Bool(bool),
    Integer,
    Float,
    Str,
    Symbol,
    Hash,
    Array,
    Time,
    Date,
    BigDecimal,
    Other,
}

impl Kind {
    /// A plain value of some other Avro shape: the avro gem's validator rejects it for numbers, strings and the
    /// container types.
    fn is_foreign_scalar(self) -> bool {
        matches!(
            self,
            Kind::Nil | Kind::Bool(_) | Kind::Integer | Kind::Float | Kind::Str | Kind::Symbol | Kind::Hash | Kind::Array
        )
    }
}

pub struct Writer<'a> {
    ruby: &'a Ruby,
    plan: &'a Plan,
    string: RClass,
    hash: RClass,
    array: RClass,
    time: RClass,
    big_decimal: RClass,
    date: RClass,
    utf8: Index,
    ascii: Index,
    binary: Index,
}

/// The Julian day number of 1970-01-01.
const EPOCH_JD: i64 = 2_440_588;

fn same(a: RClass, b: RClass) -> bool {
    a.as_raw() == b.as_raw()
}

impl<'a> Writer<'a> {
    pub fn new(ruby: &'a Ruby, plan: &'a Plan) -> Self {
        Writer {
            ruby,
            plan,
            string: ruby.class_string(),
            hash: ruby.class_hash(),
            array: ruby.class_array(),
            time: ruby.class_time(),
            big_decimal: ruby.get_inner(&BIG_DECIMAL),
            date: ruby.get_inner(&DATE),
            utf8: ruby.utf8_encindex(),
            ascii: ruby.usascii_encindex(),
            binary: ruby.ascii8bit_encindex(),
        }
    }

    fn kind(&self, v: Value) -> Kind {
        if v.is_nil() {
            return Kind::Nil;
        }
        if v.as_raw() == self.ruby.qtrue().as_raw() {
            return Kind::Bool(true);
        }
        if v.as_raw() == self.ruby.qfalse().as_raw() {
            return Kind::Bool(false);
        }
        if Integer::from_value(v).is_some() {
            return Kind::Integer;
        }
        if Float::from_value(v).is_some() {
            return Kind::Float;
        }
        if Symbol::from_value(v).is_some() {
            return Kind::Symbol;
        }
        let class = v.class();
        if same(class, self.string) {
            Kind::Str
        } else if same(class, self.hash) {
            Kind::Hash
        } else if same(class, self.array) {
            Kind::Array
        } else if same(class, self.time) {
            Kind::Time
        } else if same(class, self.big_decimal) {
            Kind::BigDecimal
        } else if same(class, self.date) {
            Kind::Date
        } else {
            Kind::Other
        }
    }

    /// Encodes `v` with node `index`, appending to `out`. On failure `out` may hold a partial write.
    pub fn datum(&self, index: usize, v: Value, out: &mut Vec<u8>) -> Step {
        let kind = self.kind(v);
        match self.plan.node(index) {
            Node::Null => match kind {
                Kind::Nil => Ok(()),
                _ => Err(Fail::Mismatch),
            },
            Node::Boolean => match kind {
                Kind::Bool(b) => {
                    out.push(b as u8);
                    Ok(())
                }
                _ => Err(Fail::Mismatch),
            },
            Node::Int => self.integer(kind, v, i32::MIN as i64, i32::MAX as i64, out),
            Node::Long => self.integer(kind, v, i64::MIN, i64::MAX, out),
            Node::Float => match kind {
                Kind::Float => {
                    let f = Float::from_value(v).ok_or(Fail::Unsure)?.to_f64();
                    if f.is_nan() {
                        return Err(Fail::Unsure);
                    }
                    out.extend_from_slice(&(f as f32).to_le_bytes());
                    Ok(())
                }
                k => Err(not_number(k)),
            },
            Node::Double => match kind {
                Kind::Float => {
                    let f = Float::from_value(v).ok_or(Fail::Unsure)?.to_f64();
                    out.extend_from_slice(&f.to_le_bytes());
                    Ok(())
                }
                k => Err(not_number(k)),
            },
            Node::Bytes => match kind {
                Kind::Str => {
                    let s = RString::from_value(v).ok_or(Fail::Unsure)?;
                    // SAFETY: copied out before any Ruby code runs.
                    write_bytes(unsafe { s.as_slice() }, out);
                    Ok(())
                }
                k => Err(not_text(k)),
            },
            Node::Str => match kind {
                Kind::Str => self.text(RString::from_value(v).ok_or(Fail::Unsure)?, out),
                k => Err(not_text(k)),
            },
            Node::Decimal { precision, scale } => match kind {
                Kind::BigDecimal => self.decimal(v, *precision, *scale, out),
                Kind::Nil => Err(Fail::Mismatch),
                _ => Err(Fail::Unsure),
            },
            Node::Date => match kind {
                Kind::Date => {
                    let jd: i64 = v.funcall("jd", ()).map_err(|_| Fail::Unsure)?;
                    let days = jd.checked_sub(EPOCH_JD).ok_or(Fail::Unsure)?;
                    if days < i32::MIN as i64 || days > i32::MAX as i64 {
                        return Err(Fail::Unsure);
                    }
                    write_long(days, out);
                    Ok(())
                }
                Kind::Nil => Err(Fail::Mismatch),
                _ => Err(Fail::Unsure),
            },
            Node::Timestamp { per_second } => match kind {
                Kind::Time => self.timestamp(v, *per_second, out),
                Kind::Nil => Err(Fail::Mismatch),
                _ => Err(Fail::Unsure),
            },
            Node::Enum { symbols } => match kind {
                Kind::Str => {
                    let s = RString::from_value(v).ok_or(Fail::Unsure)?;
                    if !self.ascii_compatible(s) {
                        return Err(Fail::Unsure);
                    }
                    // SAFETY: compared before any Ruby code runs.
                    let bytes = unsafe { s.as_slice() };
                    match symbols.iter().position(|sym| sym.as_slice() == bytes) {
                        Some(i) => {
                            write_long(i as i64, out);
                            Ok(())
                        }
                        None => Err(Fail::Mismatch),
                    }
                }
                k if k.is_foreign_scalar() => Err(Fail::Mismatch),
                _ => Err(Fail::Unsure),
            },
            Node::Array { items } => match kind {
                Kind::Array => self.array(RArray::from_value(v).ok_or(Fail::Unsure)?, *items, out),
                Kind::Hash => Err(Fail::Mismatch),
                k => Err(not_container(k)),
            },
            Node::Map { values } => match kind {
                Kind::Hash => self.map(RHash::from_value(v).ok_or(Fail::Unsure)?, *values, out),
                Kind::Array => Err(Fail::Mismatch),
                k => Err(not_container(k)),
            },
            Node::Record { fields } => match kind {
                Kind::Hash => self.record(RHash::from_value(v).ok_or(Fail::Unsure)?, fields, out),
                Kind::Array => Err(Fail::Mismatch),
                k => Err(not_container(k)),
            },
            Node::Union { members } => self.union(members, v, out),
        }
    }

    fn integer(&self, kind: Kind, v: Value, min: i64, max: i64, out: &mut Vec<u8>) -> Step {
        match kind {
            Kind::Integer => {
                let n = Integer::from_value(v).ok_or(Fail::Unsure)?.to_i64().map_err(|_| Fail::Mismatch)?;
                if n < min || n > max {
                    return Err(Fail::Mismatch);
                }
                write_long(n, out);
                Ok(())
            }
            Kind::Float => Err(Fail::Mismatch),
            k => Err(not_number(k)),
        }
    }

    fn ascii_compatible(&self, s: RString) -> bool {
        let enc = s.enc_get();
        enc == self.utf8 || ((enc == self.ascii || enc == self.binary) && is_seven_bit(s))
    }

    /// A String for an Avro string: the avro gem transcodes to UTF-8, which leaves UTF-8 bytes alone and
    /// 7-bit ASCII/binary bytes unchanged. Any other encoding is left to the pure path.
    fn text(&self, s: RString, out: &mut Vec<u8>) -> Step {
        if !self.ascii_compatible(s) {
            return Err(Fail::Unsure);
        }
        // SAFETY: copied out before any Ruby code runs.
        write_bytes(unsafe { s.as_slice() }, out);
        Ok(())
    }

    fn decimal(&self, v: Value, precision: u32, scale: u32, out: &mut Vec<u8>) -> Step {
        let text: RString = v.funcall("to_s", ()).map_err(|_| Fail::Unsure)?;
        // SAFETY: parsed before any Ruby code runs.
        let unscaled = decimal::Unscaled::parse(unsafe { text.as_slice() }, scale, precision).ok_or(Fail::Unsure)?;
        write_bytes(&unscaled.twos_complement(), out);
        Ok(())
    }

    /// Ticks since the epoch, floored: `to_i * per_second + nsec / (1e9 / per_second)`. `nsec` is already floored and
    /// non-negative, so this equals flooring the exact instant.
    fn timestamp(&self, v: Value, per_second: i64, out: &mut Vec<u8>) -> Step {
        let secs: Integer = v.funcall("to_i", ()).map_err(|_| Fail::Unsure)?;
        let secs = secs.to_i64().map_err(|_| Fail::Unsure)?;
        let nsec: i64 = v.funcall("nsec", ()).map_err(|_| Fail::Unsure)?;
        if !(0..1_000_000_000).contains(&nsec) {
            return Err(Fail::Unsure);
        }
        let ticks = secs
            .checked_mul(per_second)
            .and_then(|t| t.checked_add(nsec / (1_000_000_000 / per_second)))
            .ok_or(Fail::Unsure)?;
        write_long(ticks, out);
        Ok(())
    }

    fn array(&self, list: RArray, items: usize, out: &mut Vec<u8>) -> Step {
        let len = list.len();
        if len > 0 {
            write_long(len as i64, out);
            for i in 0..len {
                // The length is re-read: nothing here runs Ruby code that could shrink the Array, but stay safe.
                if i >= list.len() {
                    return Err(Fail::Unsure);
                }
                let item: Value = list.entry(i as isize).map_err(|_| Fail::Unsure)?;
                self.datum(items, item, out)?;
            }
        }
        out.push(0);
        Ok(())
    }

    fn map(&self, hash: RHash, values: usize, out: &mut Vec<u8>) -> Step {
        let len = hash.len();
        if len > 0 {
            write_long(len as i64, out);
            let mut result: Step = Ok(());
            let walk = hash.foreach(|key: Value, value: Value| {
                let step = self.map_entry(key, value, values, out);
                if step.is_err() {
                    result = step;
                    return Ok(ForEach::Stop);
                }
                Ok(ForEach::Continue)
            });
            walk.map_err(|_| Fail::Unsure)?;
            result?;
        }
        out.push(0);
        Ok(())
    }

    fn map_entry(&self, key: Value, value: Value, values: usize, out: &mut Vec<u8>) -> Step {
        if self.kind(key) != Kind::Str {
            return Err(Fail::Unsure);
        }
        let key = RString::from_value(key).ok_or(Fail::Unsure)?;
        // The avro gem's union check raises on a key that is not valid in its encoding; leave those to it.
        if key.enc_coderange_scan() == Coderange::Broken {
            return Err(Fail::Unsure);
        }
        self.text(key, out)?;
        self.datum(values, value, out)
    }

    /// The datum must be the Hash `to_datum` builds: String keys, one per field, in field order. Anything else is
    /// left to the pure path.
    fn record(&self, hash: RHash, fields: &[(Vec<u8>, usize)], out: &mut Vec<u8>) -> Step {
        if hash.len() != fields.len() {
            return Err(Fail::Unsure);
        }
        let mut index = 0usize;
        let mut result: Step = Ok(());
        let walk = hash.foreach(|key: Value, value: Value| {
            let step = self.record_entry(fields, index, key, value, out);
            index += 1;
            if step.is_err() {
                result = step;
                return Ok(ForEach::Stop);
            }
            Ok(ForEach::Continue)
        });
        walk.map_err(|_| Fail::Unsure)?;
        result?;
        if index != fields.len() {
            return Err(Fail::Unsure);
        }
        Ok(())
    }

    fn record_entry(&self, fields: &[(Vec<u8>, usize)], index: usize, key: Value, value: Value, out: &mut Vec<u8>) -> Step {
        let (name, node) = fields.get(index).ok_or(Fail::Unsure)?;
        let key = match self.kind(key) {
            Kind::Str => RString::from_value(key).ok_or(Fail::Unsure)?,
            _ => return Err(Fail::Unsure),
        };
        // SAFETY: compared before any Ruby code runs.
        if unsafe { key.as_slice() } != name.as_slice() {
            return Err(Fail::Unsure);
        }
        self.datum(*node, value, out)
    }

    /// The first member the value fits, as the avro gem picks it. A member this encoder is unsure about stops the
    /// search: the pure path might pick it.
    fn union(&self, members: &[usize], v: Value, out: &mut Vec<u8>) -> Step {
        let start = out.len();
        for (branch, member) in members.iter().enumerate() {
            write_long(branch as i64, out);
            match self.datum(*member, v, out) {
                Ok(()) => return Ok(()),
                Err(Fail::Mismatch) => out.truncate(start),
                Err(Fail::Unsure) => return Err(Fail::Unsure),
            }
        }
        Err(Fail::Mismatch)
    }
}

fn not_number(kind: Kind) -> Fail {
    match kind {
        Kind::Nil | Kind::Bool(_) | Kind::Str | Kind::Symbol | Kind::Hash | Kind::Array => Fail::Mismatch,
        _ => Fail::Unsure,
    }
}

fn not_text(kind: Kind) -> Fail {
    match kind {
        Kind::Nil | Kind::Bool(_) | Kind::Integer | Kind::Float | Kind::Symbol | Kind::Hash | Kind::Array => Fail::Mismatch,
        _ => Fail::Unsure,
    }
}

fn not_container(kind: Kind) -> Fail {
    match kind {
        Kind::Nil | Kind::Bool(_) | Kind::Integer | Kind::Float | Kind::Str | Kind::Symbol => Fail::Mismatch,
        _ => Fail::Unsure,
    }
}

fn is_seven_bit(s: RString) -> bool {
    // SAFETY: read before any Ruby code runs.
    unsafe { s.as_slice() }.is_ascii()
}
