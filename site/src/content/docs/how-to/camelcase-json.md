---
title: "How to use camelCase JSON keys"
description: "Keep snake_case field names in Ruby while reading and writing camelCase keys for an outside API."
sidebar:
  label: "Use camelCase JSON keys"
  order: 3
---

A greenhouse monitoring service sends and expects `plantedOn`, and you want `planted_on` to stay the Ruby name.

## 1. Map the names

Declare the fields, then call `serialize :json` with the Ruby name as key and the outside name as value. It raises on a key that isn't a declared field, so it goes after the fields.

```ruby run
class Seedbed < FieldStruct::Base
  required :bed_label, :string
  optional :planted_on, :date, format: :iso8601
  optional :soil_type, :string

  serialize :json, bed_label: 'bedLabel', planted_on: 'plantedOn'
end
```

Anything missing from the mapping keeps its own name, like `soil_type` here.

## 2. Write

`as_json` and `to_json` emit the outside names. Every other view of the object, `attributes`, `to_h` and pattern matching, stays with the Ruby names.

```ruby run
bed = Seedbed.new(bed_label: 'North 4', planted_on: '2026-04-14')

bed.as_json     # => {bedLabel: "North 4", plantedOn: "2026-04-14", soil_type: nil}
bed.attributes  # => {bed_label: "North 4", planted_on: Date.new(2026, 4, 14), soil_type: nil}
```

## 3. Read

`from_json` looks for the outside name first and falls back to the Ruby name. It ends up in `new`, so coercion and validation run as always.

```ruby run
payload = '{"bedLabel":"South 2","plantedOn":"2026-02-09","soil_type":"clay"}'
south = Seedbed.from_json(payload)

south.bed_label   # => "South 2"
south.soil_type   # => "clay"
Seedbed.from_json('{"bed_label":"East 1"}').bed_label   # => "East 1"
Seedbed.from_json(bed.to_json) == bed                   # => true
```

A nested struct brings its own mapping, so a bed inside a greenhouse writes whatever key the bed class declares. A key that matches neither name is unknown, and `unknown_attributes` decides what happens to it.

## 4. Rename a field that clashes with a method

A field can't share a name with a method the struct already has, `errors` being one. Declare it under a different name and map it back.

```ruby run
class Alert < FieldStruct::Base
  required :level, :string
  optional :errors_field, :array, of: :string

  serialize :json, errors_field: 'errors'
end

Alert.new(level: 'frost', errors_field: ['sensor offline']).as_json   # => {level: "frost", errors: ["sensor offline"]}
```

## See also

- [JSON and serialization](/reference/field-struct/json-and-serialization/)
- [Class macros](/reference/field-struct/class-macros/#serialize)
- [Fields and options](/reference/field-struct/fields-and-options/)
