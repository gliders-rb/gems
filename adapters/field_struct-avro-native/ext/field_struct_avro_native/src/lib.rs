//! Avro binary encoding of datums for field_struct-avro, from a plan compiled once per writer schema.
//!
//! The encoder only writes what it is sure the pure-Ruby path (the avro gem's `DatumWriter`) would write
//! byte for byte. Anything else makes `Plan#encode` return `nil`, and the Ruby side runs the pure path,
//! which then succeeds or raises its own error.

mod plan;
mod write;

use magnus::{function, method, prelude::*, Error, RArray, RString, Ruby, Value};

use plan::Plan;

#[magnus::wrap(class = "FieldStruct::Avro::Native::Plan", free_immediately, size)]
struct RbPlan(Plan);

impl RbPlan {
    fn new(ruby: &Ruby, nodes: RArray, root: usize) -> Result<Self, Error> {
        Plan::from_ruby(nodes, root)
            .map(RbPlan)
            .map_err(|message| Error::new(ruby.exception_arg_error(), message))
    }

    fn encode(ruby: &Ruby, rb_self: &Self, datum: Value) -> Option<RString> {
        let mut out = Vec::with_capacity(256);
        write::Writer::new(ruby, &rb_self.0)
            .datum(rb_self.0.root(), datum, &mut out)
            .ok()?;
        Some(ruby.str_from_slice(&out))
    }

    fn size(&self) -> usize {
        self.0.len()
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let field_struct = ruby.define_module("FieldStruct")?;
    let avro = field_struct.define_module("Avro")?;
    let native = avro.define_module("Native")?;
    let class = native.define_class("Plan", ruby.class_object())?;
    class.define_singleton_method("new", function!(RbPlan::new, 2))?;
    class.define_method("encode", method!(RbPlan::encode, 1))?;
    class.define_method("size", method!(RbPlan::size, 0))?;
    Ok(())
}
