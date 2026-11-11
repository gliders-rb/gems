---
title: "Introspection reference"
description: "The format-neutral walk of a struct's fields that every adapter is built on: properties, node kinds, options and stability promises."
sidebar:
  badge:
    text: Unreleased
    variant: caution
  label: "Introspection"
  order: 8
---

`FieldStruct::Introspection` walks a struct's fields without changing anything, for code that exports a struct to another format. The JSON Schema, Avro and Protobuf adapters sit on top of it, and any adapter you write can too. It ships inside `field_struct` and loads with `require 'field_struct'` (FS §4.12, FS-B140 to FS-B152).

The walk reports declarations and nothing else. The adapter decides what `null` means for an optional field, which defaults to write, how types map and what a pass-through option does (FS-B151).

```ruby run
class Waypoint < FieldStruct::Base
  optional :label, :string
end

class Route < FieldStruct::Base
  required :name, :string
  optional :waypoints, :array, of: Waypoint
  serialize :json, waypoints: 'stops'
end

name, stops = FieldStruct::Introspection.properties(Route)
name.key                               # => "name"
name.field.required?                   # => true
stops.key                              # => "stops"
stops.node.element.klass == Waypoint   # => true
```

## `properties`

```ruby
Introspection.properties(klass, serialization: :json) # => Array<Property>
```

You get one `Property` for each field of `klass`, in declaration order and with inherited fields included. A struct without fields gives `[]`. `serialization` is a Symbol or String that selects which `serialize` mapping names the keys, and a format nobody declared keeps every field name (FS-B141, FS-B142).

Every call returns a fresh array of fresh objects, and nothing is cached on the class.

```ruby run
FieldStruct::Introspection.properties(Route).map(&:key)                          # => ["name", "stops"]
FieldStruct::Introspection.properties(Route, serialization: :csv).map(&:key)     # => ["name", "waypoints"]
FieldStruct::Introspection.properties(Class.new(FieldStruct::Base))              # => []
FieldStruct::Introspection.properties(Route).first.equal?(FieldStruct::Introspection.properties(Route).first)   # => false
```

## `Property`

| Reader | Returns |
|---|---|
| `field` | the class's own `FieldStruct::Field`, not a copy |
| `key` | the external name for the chosen format, always a String |
| `node` | the node for the field's type, built by `Introspection.node(field.type_instance, field.options)` |

`Field` has public readers an adapter may rely on (FS-B155): `name` (a Symbol), `type` (the resolved type class), `type_instance` (one per field), `required?`, `sensitive?`, `description`, `default`, `options`, `coercion_policy` and `rbs_type`.

`Field#default` is the raw declared default: a value or a callable, never called by the reader. `nil` means no default. A default of `false`, `0`, `''` or `[]` is a real default (FS-B156).

## Node kinds

`node(type, options = {})` picks a node class from the type instance. There are exactly four, with no shared base class, so dispatch with `case` (FS-B143).

| Node | Built for | Readers |
|---|---|---|
| `ScalarNode` | every other type: `:string`, `:integer`, `:value`, custom types and the rest | `type`, `options` |
| `ArrayNode` | `Types::Array` | `type`, `options`, `element` |
| `UnionNode` | `Types::Union` | `type`, `members` |
| `StructNode` | `Types::Nested` | `type`, `klass` |

```ruby run
class Leg < FieldStruct::Base
  required :nights, :integer, in: 1..5
  optional :tags, :array, of: :string, element: { strict: true }
  optional :ref, :union, of: %i[integer string]
  optional :stop, Waypoint
end

nights, tags, ref, stop = FieldStruct::Introspection.properties(Leg).map(&:node)

[nights, tags, ref, stop].map { |node| node.class.name.split('::').last }
# => ["ScalarNode", "ArrayNode", "UnionNode", "StructNode"]
nights.options                        # => {in: 1..5}
tags.element.options                  # => {strict: true}
ref.members.map { |member| member.type.ruby_type }   # => [Integer, String]
stop.klass                            # => Waypoint
```

### Scalar nodes

`type` is the field's own type instance. `options` is the Hash the value is checked against, which for a field is `Field#options` itself (FS-B144).

### Array nodes

`options` is whatever the array was declared with, so it holds `of_type:` and, when given, `element:`. It is `{}` if the array is an element of another array or a member of a union.

`element` is built on first read and the same value comes back afterwards, so an adapter that overrides the array at field level never pays for the element. It is:

- a `ScalarNode` for `of: :string`, built with the `element:` options, or `{}`
- a `StructNode` for `of: Waypoint`
- `nil` when the element type is unknown or is a union. An array of unions records only the union class, so its members can't be reached from the array node
- for `of: :array`, an `ArrayNode` whose own `element` is `nil`, so an array of arrays has exactly two levels

```ruby run
class Timetable < FieldStruct::Base
  optional :days, :array, of: :array
  optional :slots, :array, of: :union
end

days, slots = FieldStruct::Introspection.properties(Timetable).map(&:node)
days.element.class.name.split('::').last   # => "ArrayNode"
days.element.element                        # => nil
slots.element                               # => nil
```

### Union nodes

`members` is a frozen Array holding one node per member in declared order. A member carries no options, so each node is built with an empty Hash (FS-B147).

### Struct nodes

`klass` is a reference and is never expanded, so the walk doesn't recurse into a struct's own properties. Call `properties(node.klass)` yourself, and use `named?` plus a definitions table to cut off self-referential structs. The walk itself can't loop (FS-B148).

## `node`

```ruby
Introspection.node(type, options = {}) # => ScalarNode | ArrayNode | UnionNode | StructNode
```

`node` builds a node for a type instance and the options Hash it is checked with. Anything that isn't an array, union or nested type becomes a `ScalarNode`, a non-type passed by mistake included.

```ruby run
count = FieldStruct::Introspection.node(FieldStruct::Types::Integer.new, in: 1..3)
count.class.name.split('::').last   # => "ScalarNode"
count.options                       # => {in: 1..3}
```

## `named?`

```ruby
Introspection.named?(klass) # => Boolean
```

True when the class has a name usable as a definition key or title. An anonymous class gives false, and so does a class under an anonymous module, whose name looks like `#<Module:0x...>::Addr`. A class in an ordinary namespace gives true (FS-B150).

```ruby run
module Alpine
  class Refuge < FieldStruct::Base; end
end

FieldStruct::Introspection.named?(Alpine::Refuge)                   # => true
FieldStruct::Introspection.named?(Class.new(FieldStruct::Base))     # => false
```

## What `options` holds

Adapters read `Field#options` through the nodes, and these are the promises (FS-B157):

- `enum:` and `in:` are as declared: an Array of Strings or Symbols, a Range or an Array.
- `round:`, `base:` and `strict:` are as declared, and `round:` and `values:` are present only when declared.
- `format:` on a string-family field is a Regexp, the declared one or the type's default.
- `format:` on a date or time field is the declared value: `nil` when none was given (the key is present), a preset Symbol such as `:iso8601`, or a String. It is never a resolved object.
- `zone:` is as written.
- `values:` on `:boolean` is the resolved Hash `{truthy: [...], falsy: [...]}`.
- Pass-through options such as `avro:`, `proto:` and `json_schema:`, and any unknown key, are present verbatim and never validated.
- An element's options are validated like a scalar field's, so a pass-through option on an `element:` raises at declaration. Pass-through options are for whole fields only (FS-B162).

```ruby run
class Climb < FieldStruct::Base
  required :gain, :float, round: 1, in: 0.0..99.9, unit: 'km'
  optional :logged, :date
end

gain, logged = FieldStruct::Introspection.properties(Climb).map(&:node)
gain.options      # => {round: 1, in: 0.0..99.9, unit: "km"}
logged.options    # => {format: nil}
```

## Stability promises

- Every `Property` and every node is frozen. The `options` Hashes belong to the struct and are frozen shallowly at most, so treat what they hold (an `enum:` Array, a `values:` Hash) as read-only (FS-B149).
- `Introspection` mutates nothing and caches nothing on the class, and calling it never changes how a struct behaves. A field redeclared after a call is a new `Field` that the next call picks up (FS-B152).
- `Metadata#serialization(format)` returns the same frozen Hash until the class redeclares that format, and `Metadata#each` yields the same `Field` objects while a field stays unchanged. A cache keyed on those objects holds exactly until the class's declarations change (FS-B159).
- Core ships no exporter: there is no `FieldStruct::JSONSchema`, no `to_json_schema`, and no format named other than `:json` (FS-B140).

## Type readers

An adapter that maps types reads them off `type_instance` (FS-B163, FS-B164).

- `ruby_type` is `Integer` for `:integer`, `Float`, `String` for the whole string family, `[TrueClass, FalseClass]` for `:boolean`, `Symbol`, `Date`, `Time`, `DateTime`, `BigDecimal`, `Object` for `:value`, `Array`, the struct class for a nested field, and the flat list of member classes for a union.
- `default_format` exists on `:uuid`, `:url`, `:email` (a Regexp) and on the date and time types (`nil`). `default_round` exists on `:float` and `:big_decimal`. Ask with `respond_to?` first, since other types don't define them.
- `Types::Union#member_types` gives the member type instances, and `Types::Nested#struct_class` gives the class.
- An optional hook on a custom type, like `json_schema`, is the adapter's convention and not core's. Check `respond_to?` on the instance and never assume the hook exists (FS-B161).

## See also

- [Build your own adapter](/adapters/build-your-own/)
- [How adapters work](/adapters/how-adapters-work/)
- [Introspection and tooling](/reference/field-struct/introspection-and-tooling/)
