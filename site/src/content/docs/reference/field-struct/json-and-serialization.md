---
title: "JSON and serialization"
description: "How as_json, to_json and from_json convert structs, how values are written, and how serialize maps Ruby names to JSON keys."
sidebar:
  order: 7
---

A struct goes out to JSON through `as_json` and `to_json` and comes back in through `from_json`. Reading runs through `new`, so JSON input gets the same coercion and validation as a Hash would. All JSON work uses Oj, never the standard library.

Rules: FS-B101 to FS-B111, FS-I8, FS-I13.

| Member | Returns |
|---|---|
| `#as_json` | a Hash with Symbol keys, one entry per field |
| `#to_json` | a JSON String |
| `.from_json(string)` | an instance |
| `.serialize(format, **mapping)` | the class, see [serialize](#serialize) |

## as_json

`as_json` builds a Hash with Symbol keys in declaration order, one entry per field, and unset optionals show up as `nil`. The `:json` mapping supplies the key names. It ignores its argument, and there is no `only:` or `except:`. Each value comes from the field's reader, so overriding a reader changes the output, but overriding `attributes` does not.

Values convert as follows:

| Value | Written as |
|---|---|
| `nil`, `true`, `false`, String, Integer, Float | itself |
| Symbol | its String |
| BigDecimal | a plain decimal String, so digits are never lost. `BigDecimal('1234567890123.4567')` becomes `"1234567890123.4567"` |
| Date, DateTime, Time | by the field's `format:`: an RFC 3339 preset as its rule says, a `strftime` String as given, and with no format the object's `iso8601`. For an array field the element's `format:` is used |
| Array | each element, by the same rules |
| Hash | its values, by the same rules |
| a struct | its own `as_json`, so its own mapping applies |
| anything else | `as_json` of the object if it responds to it, else the object itself |

Only `:value` fields reach the last row. The formats are covered in [Dates, times and zones](/reference/field-struct/dates-and-times/) for the formats.

## to_json

`to_json` is `Oj.dump(as_json, mode: :compat)`. Its argument is ignored too, so `to_json(only: [:species])` still writes every field. Symbol keys become JSON strings.

## from_json

```ruby
Klass.from_json(json_string)
```

The string is parsed with `Oj.load(string, mode: :compat, decimal_class: BigDecimal)`: numbers with a fraction or exponent arrive as BigDecimal, whole numbers as Integer. Keys map back to Ruby names and the Hash goes to `Klass.new`, so coercion, nested construction, `unknown_attributes` and `coercion_policy` act just as they do for direct construction.

What the BigDecimal parse means for each type:

- a `:decimal` field receives exactly the digits that were sent
- a `:float` field still ends up a Float
- an `:integer` field cuts `3.7` down to `3`
- a `:value` field, along with numbers inside its Hashes and Arrays, holds a BigDecimal, and `to_json` then writes it as a String
- JSON `1e400` is a finite BigDecimal. Decimal and integer fields read it and a float field refuses it

Errors:

| Input | Raises |
|---|---|
| a root that is not an object | `ArgumentError`: `from_json expects a JSON object root, got Array` |
| `null` | the same, with `got NilClass` |
| malformed JSON, including an empty or blank String | `EncodingError`: `from_json could not parse its input as JSON (<description> at line L, column C)` |

`EncodingError` is what Oj raises in this mode, and FieldStruct has no class of its own for it. It is re-raised with no `cause` and no piece of the input, so a secret inside a bad payload never reaches a log.

```ruby run
require 'bigdecimal'

class Plant < FieldStruct::Base
  required :species, :string
  optional :yield_kg, :decimal
  optional :sown, :date, format: :us
  optional :last_watered, :time, format: :iso8601
  optional :leaves, :integer
  optional :humidity, :float
  optional :notes, :value
end

json = '{"species":"Fern","yield_kg":3.250,"sown":"03/14/2026","last_watered":"2026-05-02T06:00:00Z","leaves":88.9,"humidity":5e1}'
plant = Plant.from_json(json)
plant.yield_kg                   # => BigDecimal('3.25')
plant.leaves                     # => 88
plant.humidity                   # => 50.0
plant.as_json[:yield_kg]         # => "3.25"
plant.as_json[:sown]             # => "03/14/2026"
plant.as_json[:last_watered]     # => "2026-05-02T06:00:00Z"
plant.as_json[:notes]            # => nil
plant.to_json.include?('"yield_kg":"3.25"')   # => true
Plant.new(species: 'x').to_json(only: [:species]) == Plant.new(species: 'x').to_json   # => true
Plant.from_json('{"species":"x","notes":{"depth":0.75}}').notes   # => {"depth" => BigDecimal('0.75')}

begin
  Plant.from_json('[1]')
rescue ArgumentError => e
  e.message   # => "from_json expects a JSON object root, got Array"
end

begin
  Plant.from_json('null')
rescue ArgumentError => e
  e.message   # => "from_json expects a JSON object root, got NilClass"
end

begin
  Plant.from_json('{oops')
rescue EncodingError => e
  e.message.start_with?('from_json could not parse its input as JSON')   # => true
end
```

## Round trip

`Klass.from_json(x.to_json) == x` holds for any struct, with one exception. A `:value` field comes back equal only when its content is plain JSON, since `from_json` returns numbers as BigDecimal while `to_json` writes them as Strings. Nested structs, arrays of structs, unions of structs (each member reverse-maps through its own mapping), temporal fields with any declared `format:`, and decimals all round-trip.

```ruby run
class Sample < FieldStruct::Base
  required :label, :string
  optional :rainfall_mm, :decimal
  optional :collected_at, :datetime, format: :iso8601
  optional :season_start, :date, format: '%d/%m/%Y'
  serialize :json, collected_at: 'collectedAt'
end

sample = Sample.new(label: 'gauge-7', rainfall_mm: '14.5', collected_at: '2026-09-21T18:30:00Z', season_start: '01/09/2026')
sample.to_json == Sample.from_json(sample.to_json).to_json   # => true
Sample.from_json(sample.to_json) == sample                   # => true
sample.as_json   # => {label: "gauge-7", rainfall_mm: "14.5", collectedAt: "2026-09-21T18:30:00Z", season_start: "01/09/2026"}
```

## serialize

```ruby
serialize :json, internal_name: 'externalName'
```

`serialize(format, **mapping)` renames keys for one format. The mapping keys are Ruby field names and must be declared already. Values turn into Strings, so `first: :firstName` stores `"firstName"`. The mapping is kept frozen and `metadata.serialization(format)` returns it.

The gem itself uses only `:json`. Other names, like `:csv`, are stored for other gems to read. Declaring a format again swaps out its whole mapping, and fields left out of the mapping keep their own names. A subclass starts with its parent's mappings and may map inherited fields, replace a format or add a new one. Replacing is total: a subclass that calls `serialize :json` again drops the parent's `:json` entries unless it repeats them.

The mapping works in both directions and recursively:

- `as_json` writes the external names, with nested structs using their own mappings
- `from_json` reads the external name and also takes the Ruby name. A key matching neither is unknown and follows `unknown_attributes`
- a nested struct given a Hash, and each Hash in an array of structs, goes through the nested class's own mapping
- a `:union` given a Hash tries its members in declared order. A struct member maps the keys through its own mapping and builds, and the first one that accepts wins. A non-struct member such as `:value` that accepts the raw Hash wins as is. If none accepts, the raw Hash moves on and the field's coercion policy decides
- arrays of unions, and unions inside arrays, are not reverse-mapped

`attributes`, `to_h`, `deconstruct_keys` and `deconstruct` always use Ruby names, whatever `serialize` says. Changing a mapping after a class has been read takes effect on the next call.

```ruby run
class Bed < FieldStruct::Base
  required :plot_no, :string
  serialize :json, plot_no: 'plotNo'
end

class Gardener < FieldStruct::Base
  required :nickname, :string
  optional :border, Bed
  optional :extras, :array, of: Bed
  serialize :json, nickname: :nickName, extras: 'extraBeds'
end

json = '{"nickName":"Moss","border":{"plotNo":"C-14"},"extraBeds":[{"plot_no":"C-15"}]}'
gardener = Gardener.from_json(json)
gardener.nickname              # => "Moss"
gardener.border.plot_no        # => "C-14"
gardener.extras.first.plot_no  # => "C-15"
gardener.as_json               # => {nickName: "Moss", border: {plotNo: "C-14"}, extraBeds: [{plotNo: "C-15"}]}
gardener.attributes.keys       # => [:nickname, :border, :extras]
Gardener.from_json('{"nickname":"Fen"}').nickname   # => "Fen"
Gardener.metadata.serialization(:json)   # => {nickname: "nickName", extras: "extraBeds"}
Gardener.metadata.serialization(:csv)    # => {}
```

You can't declare a field named after a reserved method such as `errors`. Declare it under another name and map it, like `serialize :json, errors_field: 'errors'`. See [Fields and options](/reference/field-struct/fields-and-options/).

## See also

- [Dates, times and zones](/reference/field-struct/dates-and-times/)
- [Class macros](/reference/field-struct/class-macros/)
- [Introspection and tooling](/reference/field-struct/introspection-and-tooling/)
- [Use camelCase JSON keys](/how-to/camelcase-json/)
