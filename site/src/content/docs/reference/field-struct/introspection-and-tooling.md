---
title: "Introspection and tooling"
description: "Reading a struct's declarations with Metadata and Field, describing a class, generating RBS, scaffolding a class from JSON, and how sensitive fields are masked."
sidebar:
  order: 9
---

Every struct class can tell you what it declares. `Klass.metadata` lists the fields, `describe` prints them for a reader, `metadata.to_h` gives a program plain data, and two helpers write code on your behalf: `FieldStruct::RBS` generates signatures and `FieldStruct::Scaffold` drafts a class from a JSON sample. The page also explains how `sensitive: true` keeps secrets out of logs.

Rules: FS-B115, FS-B119 to FS-B122, FS-B127 to FS-B139, FS-B153, FS-B154, FS-B155 to FS-B160, FS-I15, FS-I17. The neutral walk used by exporters is on [Introspection reference](/adapters/introspection/).

## Metadata

`Klass.metadata` is a `FieldStruct::Metadata`, one per class. It includes `Enumerable` and yields `Field` objects in declaration order.

| Member | Returns |
|---|---|
| `#[](name)` | the `Field`, or `nil`. A String or Symbol works |
| `#names` | the field names, a new Array each call |
| `#each` and `Enumerable` | the fields |
| `#to_h` | the schema view below when called without a block, plain `Enumerable#to_h` with one |
| `#serialization(format)` | the frozen mapping, or an empty frozen Hash when the format was never declared |
| `#serializations` | `{format => mapping}` |
| `#describe` | a multi-line String |
| `#inspect` | `#<FieldStruct::Metadata fields=[:a, :b]>`, plus ` serializations=[:json]` when any |

`Base.attribute_names` and `#attribute_names` return the same names as `metadata.names`.

Exporters count on a few identity guarantees. A format returns the same frozen mapping Hash on every call until it is declared again. A field that hasn't changed returns the same `Field` object, and redeclaring a name creates a new one. A subclass begins with its parent's `Field` objects, so `Child.metadata[:x].equal?(Parent.metadata[:x])` holds until the child redeclares `:x`.

```ruby run
module Conservatory
  class Bed < FieldStruct::Base
    required :habitat, :string
  end

  class Plant < FieldStruct::Base
    required :species, :string, desc: 'Latin binomial'
    optional :leaves, :integer, in: 1..5000
    optional :tags, :array, of: :string
    optional :bed, Bed
    optional :token, :string, sensitive: true
    serialize :json, leaves: 'leafCount'
  end
end

metadata = Conservatory::Plant.metadata
metadata.names                         # => [:species, :leaves, :tags, :bed, :token]
metadata[:species].required?           # => true
metadata['leaves'].options             # => {in: 1..5000}
metadata[:nope]                        # => nil
metadata.map(&:name).first(2)          # => [:species, :leaves]
metadata.serialization(:json)          # => {leaves: "leafCount"}
metadata.inspect                       # => "#<FieldStruct::Metadata fields=[:species, :leaves, :tags, :bed, :token] serializations=[:json]>"
metadata.serialization(:json).equal?(metadata.serialization(:json))   # => true
```

## Field

A `Field` is frozen as soon as it is built. These readers are public API: `name`, `type`, `type_instance`, `required?`, `sensitive?`, `default`, `options`, `coercion_policy`, `description`, `desc` and `rbs_type`. [Fields and options](/reference/field-struct/fields-and-options/) covers what each one promises.

`Field#inspect` is `#<FieldStruct::Field :name Type flag... part...>`. After the name comes the type (`String`, `BigDecimal`, `Nested(Bed)`, `Union(String | Integer)`), then `required`, `sensitive`, `default=...` for a non-nil default, `coercion_policy=...`, `description="..."`, `rbs_type="..."`, and each stored option as `key=value` in option order. `pp` on a `Metadata` prints one field per line.

```ruby run
metadata[:species].inspect   # => '#<FieldStruct::Field :species String required description="Latin binomial">'
metadata[:tags].inspect      # => "#<FieldStruct::Field :tags Array of_type=String>"
metadata[:bed].inspect       # => "#<FieldStruct::Field :bed Nested(Bed)>"
metadata[:token].inspect     # => "#<FieldStruct::Field :token String sensitive>"
```

## metadata.to_h

Called without a block, `to_h` returns `{field_name => schema}`. A schema has these keys in this order: `type` (the short class name), `ruby_type` (full class names joined by ` | `), `required`, `default`, `options` and `description`. `rbs_type` follows only when set, and so does `sensitive: true`. Values are reduced to primitives: a Class becomes its short name, a type instance its short class name (`"Nested"` for a nested element), Arrays and Hashes recurse, and a callable default turns into `"<callable>"`.

```ruby run
metadata.to_h[:leaves]  # => {type: "Integer", ruby_type: "Integer", required: false, default: nil, options: {in: 1..5000}, description: nil}
metadata.to_h[:token][:sensitive]       # => true
metadata.to_h[:species][:description]   # => "Latin binomial"
metadata.to_h[:tags][:options]          # => {of_type: "String"}
metadata.to_h[:bed][:ruby_type]         # => "Conservatory::Bed"
```

## describe

`Klass.describe` prints the class name, a newline, then `metadata.describe`. Anonymous classes show up as `AnonymousFieldStruct`. `Metadata#describe` gives `(no fields)` when empty and otherwise one line per field:

```
  name (Label, required|optional[, sensitive]) — "description" — key: value, ... — accepts ... — element accepts ...
```

Every segment after the first parenthesis is optional and starts with an em dash and a space:

1. The description, as a quoted String. It is the only free text `describe` prints.
2. The declared options that aren't nil.
3. `accepts`: the options the type takes, a `*` marking required ones, with their shapes and any presets.
4. `element accepts`, for arrays only: the option names of the element type.

`Label` is the short name of the type class (`String`, `BigDecimal`, `Array`). The exception is a single nested struct, which shows the struct's own short name so you know which class to describe next. An array of structs keeps the label `Array` and shows `of_type: Nested(Bed)`.

```ruby run
lines = Conservatory::Plant.describe.lines.map(&:chomp)
lines.first                  # => "Conservatory::Plant"
lines[1]                     # => '  species (String, required) — "Latin binomial" — accepts format (Regexp | Symbol), enum (Array), strict (TrueClass | FalseClass)'
lines[3]                     # => "  tags (Array, optional) — of_type: String — accepts of* (Symbol | String | Class), element (Hash) — element accepts format, enum, strict"
lines[4]                     # => "  bed (Bed, optional)"
```

## Sensitive fields

`sensitive: true` works on any type, nested structs, arrays and unions included. It changes how a value is displayed and nothing more:

- `inspect` and `pp` print `[FILTERED]` where a non-nil value would be, even for a raw value kept after a `:keep_raw` failure, and inside nested structs and arrays of them. `nil` still prints as `nil`, so an unset secret looks different from a set one.
- `Field#sensitive?` is false by default and `sensitive: false` is accepted. The flag isn't part of `options`. It appears in `Field#inspect`, in `metadata.to_h` (only when set) and in `describe`, and a subclass inherits it along with the field.
- Data paths are not masked (FS-I15). `attributes`, `to_h`, `as_json`, `to_json`, readers and pattern matching carry the real value on purpose. Before you log or send a hash, filter it yourself with `metadata[...].sensitive?`.
- Error messages hold no values, so the `errors:` suffix of `inspect` can't leak one.

```ruby run
class Logger < FieldStruct::Base
  required :contact, :email
  optional :upload_key, :string, sensitive: true
  optional :channels, :integer
end

logger = Logger.new(contact: 'keeper@example.com', upload_key: 'key_live_5678')
logger.inspect    # => '#<Logger contact: "keeper@example.com", upload_key: [FILTERED], channels: nil>'
logger.upload_key # => "key_live_5678"
logger.to_h[:upload_key]   # => "key_live_5678"
Logger.new(contact: 'keeper@example.com').inspect.include?('upload_key: nil')   # => true

safe = logger.to_h.reject { |name, _| Logger.metadata[name].sensitive? }
safe.keys         # => [:contact, :channels]
```

## RBS

```ruby
FieldStruct::RBS.generate(klass)               # => String
FieldStruct::RBS.type_for(field, nullable: nil) # => String
```

`generate` returns an RBS String: a three-line header comment, then the class block inside `module` blocks that mirror the namespace. The block has an `attr_reader` and a writer for each field the class declares itself, and skips a field inherited unchanged. The header notes that the types describe a valid instance. An invalid one can hold other values, so check `valid?`.

Readers of required fields get no `?`, and writers always accept `nil`. Anything that isn't a `Base` subclass, `Base` itself, or an anonymous class raises `ArgumentError`.

`type_for` takes a `Field` and returns its RBS type. With `nullable: nil` the type is nullable unless the field is required. The base type is the first of these that exists: `rbs_type:` on the field, `rbs_type` on the type, then the derived type. An override containing `|`, `&` or `^` is wrapped in parentheses.

| Field | RBS type |
|---|---|
| string family, `:binary` | `::String` |
| `:symbol`, `:integer`, `:float` | `::Symbol`, `::Integer`, `::Float` |
| `:decimal` | `::BigDecimal` |
| `:boolean` | `bool` |
| `:date`, `:time`, `:datetime` | `::Date`, `::Time`, `::DateTime` |
| `:value` | `untyped` |
| a nested struct | its full name, such as `::Conservatory::Bed` |
| `:array` | `::Array[E]`, with `?` on scalar elements (`::Array[::String?]`) and none on struct elements |
| `:union` | `(::Integer | ::Float)`, or `untyped` if any member is `untyped` |
| custom `ruby_type` of `Array`, `Hash`, `Range` | `::Array[untyped]`, `::Hash[untyped, untyped]`, `::Range[untyped]` |
| custom `ruby_type` of `Object` | `untyped` |

```ruby run
class Orchid < FieldStruct::Base
  required :species, :string
  optional :blooms, :integer
  optional :tags, :array, of: :string
  optional :humidity, :union, of: %i[integer float]
  optional :photo, :value
  optional :label_path, :string, rbs_type: '::Pathname'
end

rbs = FieldStruct::RBS.generate(Orchid)
rbs.lines.first                                              # => "# Generated by FieldStruct::RBS. Types describe a valid instance: an\n"
rbs.include?('attr_reader species: ::String')                # => true
rbs.include?('def species=: (::String? value) -> ::String?') # => true
FieldStruct::RBS.type_for(Orchid.metadata[:blooms])          # => "::Integer?"
FieldStruct::RBS.type_for(Orchid.metadata[:species])         # => "::String"
FieldStruct::RBS.type_for(Orchid.metadata[:species], nullable: true)   # => "::String?"
FieldStruct::RBS.type_for(Orchid.metadata[:humidity])        # => "(::Integer | ::Float)?"
FieldStruct::RBS.type_for(Orchid.metadata[:tags])            # => "::Array[::String?]?"
FieldStruct::RBS.type_for(Orchid.metadata[:photo])           # => "untyped"
FieldStruct::RBS.type_for(Orchid.metadata[:label_path])      # => "::Pathname?"
```

For Actionable classes, see [RBS for your actions](/reference/actionable/rbs/).

## Scaffold

```ruby
FieldStruct::Scaffold.from_json(input, class_name: 'Generated')   # => String
```

Drafts source for a class, plus the classes nested in it, from one JSON example or an array of same-shaped ones. `input` is a JSON String or data that is already parsed. The result is a starting point, not a finished model: guesses show up as trailing comments instead of committing to risky types.

- Nested objects turn into classes of their own, written ahead of their parent. Names are the camelized key, and a repeated name gets a number starting from 2.
- Types: booleans become `:boolean`, integers `:integer`, floats or a mix of the two `:float`, strings always `:string` (even when they look numeric), an object a nested class, an array `:array, of: X`, and mixed kinds `:value`.
- A field is `required` only when every sample has it and it is never null or blank.
- Comments flag what the samples can't settle: `present 1/2`, `empty/null in 1/2`, numeric-looking strings, a short list of repeated values that might be an `enum:`, mixed types, and empty arrays.
- Keys become valid Ruby names: camelCase turns into snake_case, and keywords or reserved names get a `_field` suffix. When a name differs from its key, a single `serialize :json, name: "key"` line follows the field lines.

The output loads, and the generated class reads the original example through `from_json`. Bad input raises `ArgumentError`: `expected a JSON object or array of objects, got Integer`, `no samples to scaffold from`, or `every sample must be a JSON object`.

```ruby run
sample = '[{"id": 1, "bedName": "North", "tags": ["a"], "border": {"habitat": "fen"}, "flowering": true}, {"id": 2, "bedName": "South", "tags": [], "border": {"habitat": "heath"}, "moisture": 1.5}]'
source = FieldStruct::Scaffold.from_json(sample, class_name: 'Planting')
source.lines.map(&:chomp).reject(&:empty?)[0]   # => "class Border < FieldStruct::Base"
source.include?('required :bed_name, :string')            # => true
source.include?('optional :tags, :array, of: :string # empty/null in 1/2')   # => true
source.include?('optional :moisture, :float # present 1/2')  # => true
source.include?('serialize :json, bed_name: "bedName"')   # => true

Object.class_eval(source)
Planting.from_json('{"id": 3, "bedName": "East", "border": {"habitat": "moor"}}').valid?   # => true
```

## Introspection for exporters

`FieldStruct::Introspection.properties(klass, serialization: :json)` returns a neutral walk of a struct, meant for code that exports it to another schema language such as JSON Schema, Avro or Protobuf. That is reference material for adapter authors, so it sits with the adapters. See [Introspection reference](/adapters/introspection/).

## See also

- [Fields and options](/reference/field-struct/fields-and-options/)
- [Instance API](/reference/field-struct/instance-api/)
- [Introspection reference](/adapters/introspection/)
- [Keep secrets out of logs](/how-to/hide-sensitive-values/)
