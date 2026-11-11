---
title: "Exceptions"
description: "Every exception FieldStruct raises, what triggers it, what it carries, and which errors come from Ruby or Oj instead."
sidebar:
  order: 10
---

FieldStruct has only three exception classes of its own. Bad input is normally recorded on `errors`, not raised, and the three classes below are for the cases where raising is the whole point. Everything else is a standard Ruby error whose message is a full sentence and never includes an input value.

Rules: section 4.5 of the field_struct spec, FS-I5, FS-I7, FS-I20.

```
StandardError
  FieldStruct::Error
    FieldStruct::CoercionError         #field_name, #original
    FieldStruct::ImmutableError
    FieldStruct::UnknownAttributeError #keys
```

One `rescue FieldStruct::Error` catches all three.

## FieldStruct::CoercionError

A setter raises it when a type can't read a value and the effective [coercion policy](/reference/field-struct/validation-and-errors/) is `:raise`. The previous value stays in place.

| Reader | Value |
|---|---|
| `message` | `could not coerce <InputClass> input for <field>: <reason>` |
| `field_name` | the field, as a Symbol |
| `original` | the exception the type raised. It is also the `cause` |

Through `new`, `assign_attributes` and `with`, the first bad key raises. For arrays the message includes an index phrase like `element at index 1: ...`. The reason names classes, never values.

```ruby run
class Anemometer < FieldStruct::Base
  coercion_policy :raise
  required :gust_kph, :float
  optional :calibrated_on, :date
end

begin
  Anemometer.new(gust_kph: 'breezy')
rescue FieldStruct::CoercionError => e
  e.field_name             # => :gust_kph
  e.original.class         # => ArgumentError
  e.cause.equal?(e.original)   # => true
  e.message.start_with?('could not coerce String input for gust_kph:')   # => true
end

vane = Anemometer.new(gust_kph: 35)
begin
  vane.calibrated_on = 'last spring'
rescue FieldStruct::CoercionError => e
  e.field_name   # => :calibrated_on
end
vane.calibrated_on   # => nil
```

## FieldStruct::ImmutableError

Any setter, and `assign_attributes`, raises it on an instance of an `immutable!` class after `new` has finished, before any coercion happens. The message is `<Class> is immutable; cannot reassign <field>`, and an anonymous class prints as `#<Class:0x...>`.

```ruby run
class Benchmark < FieldStruct::Base
  immutable!
  required :elevation_m, :integer
end

begin
  Benchmark.new(elevation_m: 120).assign_attributes(elevation_m: 125)
rescue FieldStruct::ImmutableError => e
  e.message   # => "Benchmark is immutable; cannot reassign elevation_m"
end
```

## FieldStruct::UnknownAttributeError

`new`, `assign_attributes` and `with` raise it on a class declared with `unknown_attributes :raise`, before anything is assigned. `keys` holds the unknown keys as Symbols in input order, and the message reads `unknown attribute(s) for <Class>: :a, :b`.

```ruby run
class Seedbed < FieldStruct::Base
  unknown_attributes :raise
  required :label, :string
end

begin
  Seedbed.new(label: 'north', soil: 'clay', shade: 2)
rescue FieldStruct::UnknownAttributeError => e
  e.keys      # => [:soil, :shade]
  e.message   # => "unknown attribute(s) for Seedbed: :soil, :shade"
end
```

## Ruby exceptions

| Class | When |
|---|---|
| `ArgumentError` | `new` or `assign_attributes` given something other than a Hash or `to_hash` object; `with` given a positional argument; a declaration problem (bad option value, an option on the wrong type, a reserved name, a bad `zone:`, an unknown preset); an unknown class macro value; `from_json` given a root that is not an object; the `RBS` and `Scaffold` helpers given bad input; `serialize` naming an undeclared field |
| `KeyError` | an unknown type name, at declaration |
| `NameError` | `use_alias!` when the constant already exists and is something else |
| `FrozenError` | a setter on an instance made with `frozen!` |
| `NotImplementedError` | a custom type without `coerce` or `ruby_type` |
| `EncodingError` | `from_json` given malformed JSON. This is the class Oj raises, and FieldStruct defines none of its own |

Declaration problems raise while the class body runs, never at first use, so a typo fails at load time (FS-I19). The declaration messages are listed on [Fields and options](/reference/field-struct/fields-and-options/#declaration-errors).

The messages from `new` and `with` name the class and the class of the input, never its value:

```ruby run
begin
  Seedbed.new(%w[north south])
rescue ArgumentError => e
  e.message   # => "Seedbed.new expects a Hash (or an object responding to #to_hash), got Array"
end

begin
  Class.new(FieldStruct::Base) { required :species, :stirng }
rescue KeyError => e
  e.message   # => "no FieldStruct type registered for :stirng"
end

begin
  Seedbed.new(label: 'east').freeze.label = 'west'
rescue FrozenError
  :frozen   # => :frozen
end
```

## What does not raise

Each of these lands on `errors` and leaves the object usable:

- a missing required field: `"is required"`
- a failed `format:`, `enum:` or `in:`: `"is invalid"`
- a value a type cannot read under `:keep_raw` or `:replace`: `"could not be coerced: ..."`
- a failed cross-field validator

Exceptions from your own validators or from a callable default propagate unchanged. So do errors raised while building a nested struct (`UnknownAttributeError`, `CoercionError`, `ArgumentError`): they come through as they are, and the parent's policy doesn't handle them.

## See also

- [Validation and errors](/reference/field-struct/validation-and-errors/)
- [Class macros](/reference/field-struct/class-macros/)
- [Fields and options](/reference/field-struct/fields-and-options/)
- [Coercion versus validation](/explanation/coercion-and-validation/)
