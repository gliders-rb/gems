//! The encoding plan: a flat list of nodes, children referenced by index so recursive records need no cycles.
//!
//! The Ruby side (`FieldStruct::Avro::Native::Compiler`) builds the description from a parsed `Avro::Schema`;
//! each node is an Array whose first element is a tag.

use magnus::{RArray, RString, Value};

pub const NULL: i64 = 0;
pub const BOOLEAN: i64 = 1;
pub const INT: i64 = 2;
pub const LONG: i64 = 3;
pub const FLOAT: i64 = 4;
pub const DOUBLE: i64 = 5;
pub const BYTES: i64 = 6;
pub const STRING: i64 = 7;
pub const DECIMAL: i64 = 8;
pub const DATE: i64 = 9;
pub const TIMESTAMP: i64 = 10;
pub const ENUM: i64 = 11;
pub const ARRAY: i64 = 12;
pub const MAP: i64 = 13;
pub const RECORD: i64 = 14;
pub const UNION: i64 = 15;

#[derive(Debug)]
pub enum Node {
    Null,
    Boolean,
    Int,
    Long,
    Float,
    Double,
    Bytes,
    Str,
    /// Unscaled digits must stay below `10**precision`.
    Decimal { precision: u32, scale: u32 },
    Date,
    /// Ticks per second: 1_000 (millis), 1_000_000 (micros) or 1_000_000_000 (nanos).
    Timestamp { per_second: i64 },
    Enum { symbols: Vec<Vec<u8>> },
    Array { items: usize },
    Map { values: usize },
    Record { fields: Vec<(Vec<u8>, usize)> },
    Union { members: Vec<usize> },
}

#[derive(Debug)]
pub struct Plan {
    nodes: Vec<Node>,
    root: usize,
}

impl Plan {
    pub fn root(&self) -> usize {
        self.root
    }

    pub fn len(&self) -> usize {
        self.nodes.len()
    }

    pub fn node(&self, index: usize) -> &Node {
        &self.nodes[index]
    }

    pub fn from_ruby(list: RArray, root: usize) -> Result<Self, String> {
        let mut nodes = Vec::with_capacity(list.len());
        for i in 0..list.len() {
            let item: RArray = list.entry(i as isize).map_err(|e| format!("node {i}: {e}"))?;
            nodes.push(node(item).map_err(|e| format!("node {i}: {e}"))?);
        }
        let plan = Plan { nodes, root };
        plan.check()?;
        Ok(plan)
    }

    fn check(&self) -> Result<(), String> {
        let n = self.nodes.len();
        let ok = |i: usize| if i < n { Ok(()) } else { Err(format!("child index {i} out of range")) };
        ok(self.root)?;
        for node in &self.nodes {
            match node {
                Node::Array { items } => ok(*items)?,
                Node::Map { values } => ok(*values)?,
                Node::Record { fields } => fields.iter().try_for_each(|(_, i)| ok(*i))?,
                Node::Union { members } => {
                    members.iter().try_for_each(|i| ok(*i))?;
                    if members.iter().any(|i| matches!(self.nodes[*i], Node::Union { .. })) {
                        return Err("a union inside a union".into());
                    }
                }
                Node::Decimal { precision, .. } if *precision == 0 => return Err("decimal precision 0".into()),
                _ => {}
            }
        }
        Ok(())
    }
}

fn at<T: magnus::TryConvert>(item: RArray, i: isize) -> Result<T, String> {
    item.entry(i).map_err(|e| e.to_string())
}

fn bytes_of(value: Value) -> Result<Vec<u8>, String> {
    let s = RString::from_value(value).ok_or("expected a String")?;
    // SAFETY: the slice is copied before any Ruby code runs.
    Ok(unsafe { s.as_slice() }.to_vec())
}

fn node(item: RArray) -> Result<Node, String> {
    let tag: i64 = at(item, 0)?;
    Ok(match tag {
        NULL => Node::Null,
        BOOLEAN => Node::Boolean,
        INT => Node::Int,
        LONG => Node::Long,
        FLOAT => Node::Float,
        DOUBLE => Node::Double,
        BYTES => Node::Bytes,
        STRING => Node::Str,
        DECIMAL => Node::Decimal { precision: at(item, 1)?, scale: at(item, 2)? },
        DATE => Node::Date,
        TIMESTAMP => {
            let per_second: i64 = at(item, 1)?;
            if ![1_000, 1_000_000, 1_000_000_000].contains(&per_second) {
                return Err(format!("timestamp unit {per_second}"));
            }
            Node::Timestamp { per_second }
        }
        ENUM => {
            let list: RArray = at(item, 1)?;
            let symbols = (0..list.len())
                .map(|i| list.entry::<Value>(i as isize).map_err(|e| e.to_string()).and_then(bytes_of))
                .collect::<Result<_, _>>()?;
            Node::Enum { symbols }
        }
        ARRAY => Node::Array { items: at(item, 1)? },
        MAP => Node::Map { values: at(item, 1)? },
        RECORD => {
            let list: RArray = at(item, 1)?;
            let mut fields = Vec::with_capacity(list.len());
            for i in 0..list.len() {
                let pair: RArray = list.entry(i as isize).map_err(|e| e.to_string())?;
                fields.push((bytes_of(at(pair, 0)?)?, at(pair, 1)?));
            }
            Node::Record { fields }
        }
        UNION => {
            let list: RArray = at(item, 1)?;
            let members = (0..list.len())
                .map(|i| list.entry::<usize>(i as isize).map_err(|e| e.to_string()))
                .collect::<Result<_, _>>()?;
            Node::Union { members }
        }
        other => return Err(format!("unknown tag {other}")),
    })
}
