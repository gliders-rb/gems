---
title: "Types"
description: "Each built-in field type in one place: the input it takes, the value it stores, its options, and when it counts as missing."
sidebar:
  order: 2
---

A type takes whatever the caller passes in and hands back the Ruby value the field keeps. All built-in types let `nil` through as `nil`. Whether a value counts as "missing" is a different question, answered by what `required` rejects, and the answer depends on the type.

Rules: FS-B52 to FS-B84, FS-I12, FS-I16. Dates and times have their own page, [Dates, times and zones](/reference/field-struct/dates-and-times/).

Two rules hold for every type. A value the type cannot read is a coercion failure, and the [coercion policy](/reference/field-struct/validation-and-errors/) decides what happens next. Also, a doubtful input is refused, never guessed (FS-I12): `'12abc'` is not 12, `'NaN'` is not a number, and a Hash is not a Symbol.

| Name | Ruby type | Missing when | Options |
|---|---|---|---|
| `:string` | `String` | nil, empty, or only whitespace | `format:`, `enum:`, `strict:` |
| `:immutable_string` | `String`, frozen | as `:string` | as `:string` |
| `:uuid` | `String` | as `:string` | as `:string`, with presets |
| `:url` | `String` | as `:string` | as `:string`, with presets |
| `:email` | `String` | as `:string` | as `:string`, with presets |
| `:binary` | `String`, ASCII-8BIT | nil or empty | as `:string` |
| `:symbol` | `Symbol` | nil | `enum:` |
| `:integer` | `Integer` | nil | `in:`, `base:`, `strict:` |
| `:float` | `Float` | nil | `round:`, `in:` |
| `:decimal`, `:big_decimal` | `BigDecimal` | nil | `round:`, `in:` |
| `:boolean` | `true` or `false` | nil | `values:` |
| `:date` | `Date` | nil | `format:`, `in:` |
| `:time` | `Time` | nil | `format:`, `in:`, `zone:` |
| `:datetime` | `DateTime` | nil | `format:`, `in:`, `zone:` |
| `:value` | any object | nil | none |
| `:array` | `Array` | nil or `[]` | `of:` (required), `element:` |
| `:union` | the members' classes | nil | `of:` (required) |
| a struct class | that class | nil | none |

These are never missing: zero, `0.0`, `false`, symbols, and a `:value` field holding `''` or `[]`. A nested struct or union is missing only when it is nil.

### Which option goes with which type

Using an option on a type that does not declare it raises at declaration, and the error lists the types that do. `strict:` fits the string family and `:integer`, for instance, while `round:` fits `:float` and `:decimal` only. The matrix below is the table above turned around, one row per option:

| Option | Types |
|---|---|
| `format:` | `:string`, `:immutable_string`, `:uuid`, `:url`, `:email`, `:binary`, `:date`, `:time`, `:datetime` |
| `enum:` | `:string` family, `:symbol` |
| `strict:` | `:string` family, `:integer` |
| `in:` | `:integer`, `:float`, `:decimal`, `:date`, `:time`, `:datetime` |
| `base:` | `:integer` |
| `round:` | `:float`, `:decimal` |
| `values:` | `:boolean` |
| `zone:` | `:time`, `:datetime` |
| `of:` | `:array`, `:union` |
| `element:` | `:array` |

## Strings

`:string` calls `to_s` on any non-nil value. A String keeps its whitespace as is, and Symbols, numbers, booleans, Hashes and Arrays all become their `to_s`.

`:immutable_string` hands back a frozen copy and leaves the input alone. `:binary` hands back a copy tagged ASCII-8BIT with the same bytes. Whitespace is data there, so only nil and `''` are missing.

| Option | Values | Effect |
|---|---|---|
| `format:` | Regexp, or a preset name for `:uuid`, `:url`, `:email` | checked after coercion, a mismatch is `"is invalid"` |
| `enum:` | Array | membership check after coercion |
| `strict:` | `true` or `false` | `true` accepts only a String, Symbol, Integer or an object with `to_str`, and refuses everything else |

`format:` is matched against the string form, and writing the `\A` and `\z` anchors is up to you. A `nil` never fails `format:` or `enum:`: optional nil is fine, and required nil reads `"is required"`. A Symbol `format:` on plain `:string`, `:immutable_string` or `:binary` goes through the declaration but is never resolved, so it never validates anything. The spec lists that as an open ambiguity. Do not rely on it.

```ruby run
class Specimen < FieldStruct::Base
  optional :tag, :string, format: /\A[a-z0-9-]+\z/, enum: %w[fern-a moss-b]
  optional :remark, :string, strict: true
  optional :latin_name, :immutable_string
  optional :spore_print, :binary
end

Specimen.new(tag: 'fern-a').valid?                       # => true
Specimen.new(tag: 'Fern A').errors[:tag]                 # => ["is invalid"]
Specimen.new(tag: 12).tag                                # => "12"
Specimen.new(remark: 1.5).valid?                         # => false
Specimen.new(remark: :damp).remark                       # => "damp"
Specimen.new(latin_name: +'x').latin_name.frozen?        # => true
Specimen.new(spore_print: 'é').spore_print.encoding == Encoding::BINARY   # => true
Specimen.new(spore_print: 'é').spore_print.bytesize      # => 2
```

### uuid, url and email

All three coerce the way `:string` does, with `format:` already set to a default. A bad value is stored as given and reads `"is invalid"`. Name a preset to tighten or loosen the check, or pass a Regexp to replace it.

| Type | Preset (`format: :name`) | Default |
|---|---|---|
| `:uuid` | `any_version`, `v4`, `v7` | `any_version` |
| `:url` | `http`, `https_only`, `any_scheme` | `http` |
| `:email` | `permissive`, `default`, `strict` | `default` |

```ruby run
class Accession < FieldStruct::Base
  optional :ref,       :uuid, format: :v4
  optional :herbarium, :url, format: :https_only
  optional :curator,   :email, format: :strict
  optional :mirror,    :url
end

Accession.new(ref: '9d1c6e7a-24b3-4f50-8a1d-0e5b7c3a9f12').valid?   # => true
Accession.new(ref: 'no-such-id').errors[:ref]                        # => ["is invalid"]
Accession.new(herbarium: 'http://example.org').valid?                # => false
Accession.new(mirror: 'http://example.org').valid?                   # => true
Accession.new(curator: 'gardener@example.org').valid?                # => true
```

An unknown preset raises at declaration: `unknown :uuid format preset :zz. Available: [:any_version, :v4, :v7]`.

## Symbols

`:symbol` leaves a Symbol alone and converts a String to one (`''` becomes `:""`). Any other input fails coercion with `expected Symbol or String, got Integer`. `enum:` runs after coercion, which is why `'full'` matches `enum: %i[full part]`.

```ruby run
class Exposure < FieldStruct::Base
  optional :light, :symbol, enum: %i[full part]
end

Exposure.new(light: 'full').light          # => :full
Exposure.new(light: 'shade').errors[:light]   # => ["is invalid"]
Exposure.new(light: 5).errors[:light].first.start_with?('could not be coerced')   # => true
```

## Numbers

### :integer

An Integer goes straight through. A String is parsed in the radix from `base:` (default 10) with the same rules as Ruby's `Integer(string, radix)`: an optional sign, whitespace around it, single underscores between digits, and a prefix only if it matches the radix. Floats and Rationals truncate toward zero. Whatever `Kernel#Integer` accepts converts, so a `Time` becomes its epoch seconds. Everything else is refused.

| Option | Values | Effect |
|---|---|---|
| `in:` | Range or Array | bounds check with `cover?` for a Range, `include?` for an Array |
| `base:` | Integer from 2 to 36 | radix for String input only. `base: nil` means 10 |
| `strict:` | `true` or `false` | accept only whole numbers: `12.0` yes, `12.7` no. Strings follow the normal rules |

These strings are refused: `'3.14'`, `'12.0'`, `'1e3'`, `''`, `'1__0'`, `'_1'`, `'abc'`, and `'0x1A'` at base 10. NaN and the infinities are refused whether they arrive as Float or BigDecimal. A BigDecimal with more than 4300 integer digits is refused before any Integer is built, so a stray `1e10000000` in JSON cannot stall a parse.

```ruby run
class Tray < FieldStruct::Base
  optional :seeds, :integer, base: 16
  optional :cells, :integer, strict: true
  optional :row,   :integer, in: 1..20
  optional :spare, :integer
end

Tray.new(seeds: 'FF').seeds         # => 255
Tray.new(seeds: '0xFF').seeds       # => 255
Tray.new(cells: 24.0).cells         # => 24
Tray.new(cells: 24.5).valid?        # => false
Tray.new(row: '21').errors[:row]    # => ["is invalid"]
Tray.new(spare: '2_500').spare      # => 2500
Tray.new(spare: ' 7 ').spare        # => 7
Tray.new(spare: '012').spare        # => 12
Tray.new(spare: 8.9).spare          # => 8
Tray.new(spare: '2.75').valid?      # => false
```

### :float

A Float is kept as is. Every other input goes through Ruby's `Float(value)`, which covers Integers, BigDecimals, Rationals and numeric Strings such as `'1_000.5'`, `' 2.5 '`, `'1e3'`, `'.5'`, `'5.'` and `'017'` (17.0). These are refused: `''`, `'abc'`, `'NaN'`, `'Infinity'`, `'1e400'`, and any string with a hex prefix.

`round: n` rounds half up, with ties moving away from zero, to `n` places. It can be zero or negative and always yields a Float, so `round: 0` on `2.5` gives `3.0`. `in:` accepts a Range or an Array.

### :decimal and :big_decimal

Both names point at one class. A BigDecimal is kept. A Float is converted with 15 significant digits, so `0.1 + 0.2` reads `0.3`, while Integers and numeric Strings parse exactly. `round:` rounds half up on every call whatever `BigDecimal.mode` says, and at `round: 0` the result is still a BigDecimal. Reach for a decimal when exact digits matter, since a float carries binary rounding error.

```ruby run
require 'bigdecimal'

class Gauge < FieldStruct::Base
  optional :rain_mm, :float, round: 1, in: 0.0..500.0
  optional :yield_kg, :decimal, round: 2
  optional :harvest, :big_decimal
end

Gauge.new(rain_mm: '12.34').rain_mm        # => 12.3
Gauge.new(rain_mm: 2.5).rain_mm            # => 2.5
Gauge.new(rain_mm: 900).errors[:rain_mm]   # => ["is invalid"]
Gauge.new(rain_mm: 'NaN').valid?           # => false
Gauge.new(yield_kg: '7.125').yield_kg      # => BigDecimal('7.13')
Gauge.new(yield_kg: 0.1 + 0.2).yield_kg    # => BigDecimal('0.3')
Gauge.new(harvest: '2_400.5').harvest      # => BigDecimal('2400.5')
Gauge.new(harvest: 'abc').valid?           # => false
```

## Booleans

`:boolean` tries three things in order: the literals `true` and `false`, then the numbers `1` and `0` (`1.0` and `0.0` too), then Strings matched case-insensitively against the vocabulary. The default vocabulary is `true` and `1` for true, `false` and `0` for false. Strings are not trimmed, so `' true'` is refused.

`values:` swaps out the String vocabulary. Pass a Hash shaped `{truthy: [...], falsy: [...]}` (a scalar gets wrapped) or a preset name. It only touches Strings: the literals and `1` and `0` always work, and once your vocabulary leaves out `'true'`, that string stops being accepted.

| Preset | True | False |
|---|---|---|
| `english` (same as `english_yes_no`) | `true yes y on 1` | `false no n off 0` |
| `numeric` | `1` | `0` |

```ruby run
class Greenhouse < FieldStruct::Base
  optional :heated,  :boolean
  optional :vented,  :boolean, values: :english
  optional :misting, :boolean, values: {truthy: %w[ja], falsy: %w[nein]}
end

Greenhouse.new(heated: 'TRUE').heated       # => true
Greenhouse.new(heated: 0).heated            # => false
Greenhouse.new(heated: 'yes').valid?        # => false
Greenhouse.new(vented: 'Yes').vented        # => true
Greenhouse.new(misting: 'ja').misting       # => true
Greenhouse.new(misting: 'true').valid?      # => false
Greenhouse.new(misting: true).misting       # => true
```

## Any value

`:value` keeps whatever it is given, `''`, `[]` and `false` included, and only nil is missing. It is the escape hatch for content the gem should leave alone. That comes with two costs: nothing gets validated, and the value survives a JSON round trip only when it is plain JSON. A FieldStruct instance put in a `:value` field is validity-checked like a nested struct, so an invalid one reads `"is invalid"`.

```ruby run
class Survey < FieldStruct::Base
  optional :notes, :value
end

Survey.new(notes: {counts: [4, 'many']}).notes   # => {counts: [4, "many"]}
Survey.new(notes: '').notes                      # => ""
```

## Arrays

`:array` requires `of:`, the element type, given as a registered name, a struct class or a type class. Elements are coerced one by one, a `nil` element stays `nil`, and the result is a fresh Array. Anything that is not an Array fails coercion (`expected Array, got String`). Since `[]` counts as missing, a required array rejects nil and `[]` alike.

| Option | Values | Effect |
|---|---|---|
| `of:` | name, struct class or type class | element type, required |
| `element:` | Hash | options for the element type, applied to every element |

A single bad element fails the whole array. The message lists zero-based indexes, never the values, and stops at five indexes with `and N more`. `element:` carries coercion options (`strict:`, `base:`, `format:`) as well as checks (`enum:`, `in:`, a Regexp `format:`). Elements that fail a check produce `"element at index 1 is invalid"` or `"elements at index 0, 2 are invalid"`. The declaration validates `element:` against the element type's own rules, and a key that type does not know raises with `in element: of array field :ids, ...`.

```ruby run
class Rota < FieldStruct::Base
  required :rows, :array, of: :integer, element: {in: 1..99}
  optional :helpers, :array, of: :email
end

Rota.new(rows: %w[4 5 6]).rows                # => [4, 5, 6]
Rota.new(rows: []).errors[:rows]              # => ["is required"]
Rota.new(rows: [4, 700]).errors[:rows]        # => ["element at index 1 is invalid"]
Rota.new(rows: [4, 700, 800]).errors[:rows]   # => ["elements at index 1, 2 are invalid"]
Rota.new(rows: [4, 'x', 'y']).errors[:rows].first.start_with?('could not be coerced: elements at index 1, 2 (index 1 shown):')   # => true
Rota.new(rows: 'none').valid?                 # => false
Rota.new(rows: [4], helpers: [nil]).helpers   # => [nil]
```

Arrays of arrays are not supported. `of: :array` passes the declaration, but then every non-nil element fails to coerce. Element options do not work when the element type is `:array` or `:union`. Dates and times used as elements follow the `format:` in `element:` when written to JSON.

## Nested structs

To nest a struct, pass a `FieldStruct::Base` subclass as the type. The field accepts an instance, stored as the very same object with no copy, or a Hash, which goes to the struct's `new`. A Hash lacking required keys still builds, only invalid, and the parent field reads `"is invalid"` as soon as it is assigned. Any other input is a coercion failure reading `expected Bed or Hash, got Integer`, routed through the parent's coercion policy. Nested fields take no options of their own.

```ruby run
class Bed < FieldStruct::Base
  required :habitat, :string
  optional :plot_no, :string
end

class Gardener < FieldStruct::Base
  required :name, :string
  optional :border, Bed
  optional :outer, :array, of: Bed
end

fern = Gardener.new(name: 'Fern', border: {habitat: 'Fen'}, outer: [{habitat: 'Heath'}, Bed.new(habitat: 'Moor')])
fern.border.class                                          # => Bed
fern.outer.map(&:habitat)                                  # => ["Heath", "Moor"]
Gardener.new(name: 'Fern', border: {plot_no: '7'}).errors[:border]   # => ["is invalid"]
Gardener.new(name: 'Fern', outer: [{plot_no: '7'}]).errors[:outer]   # => ["is invalid"]
Gardener.new(name: 'Fern', border: 5).errors[:border].first.start_with?('could not be coerced')   # => true
```

:::caution
Validity is worked out at assignment time. Change a nested struct afterwards and the parent does not notice. Assign the field again, or build a new parent with `with`. See [Validation and errors](/reference/field-struct/validation-and-errors/).
:::

An error raised inside the inner `new` (`UnknownAttributeError`, `CoercionError`) travels up unchanged and skips the parent's policy. A nested class also does not pick up `unknown_attributes` from the struct that holds it.

## Unions

`:union` takes `of:` with an Array of two or more members, each a registered name or a struct class. The members are tried in declared order against the raw value and the first to accept it wins, so order matters. When none does, the failure reads `no union member (Integer | Boolean) could coerce String input`. A non-finite Float or BigDecimal is refused before any member is tried, so a `:string` member cannot end up holding `'NaN'`.

A union cannot include `:array`, since an array member would have no element type, and members take no options. If a union has to tell struct members apart, give them `unknown_attributes :raise`. Otherwise a Hash builds the first struct that accepts it.

```ruby run
class Marker < FieldStruct::Base
  optional :slot,    :union, of: %i[integer string]
  optional :label,   :union, of: %i[string integer]
  optional :flowers, :union, of: %i[integer boolean]
end

Marker.new(slot: '31').slot            # => 31
Marker.new(label: '31').label          # => "31"
Marker.new(flowers: 'maybe').valid?    # => false
Marker.new(flowers: true).flowers      # => true
```

## Custom types

A type of your own can be written and registered. That is covered on [Registries and custom types](/reference/field-struct/registries-and-custom-types/).

## See also

- [Fields and options](/reference/field-struct/fields-and-options/)
- [Dates, times and zones](/reference/field-struct/dates-and-times/)
- [Validation and errors](/reference/field-struct/validation-and-errors/)
- [Coercion versus validation](/explanation/coercion-and-validation/)
