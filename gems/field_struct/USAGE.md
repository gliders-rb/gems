# field_struct usage reference

A dense, example-first reference. Read it once; every example runs.

- [Declaring](#declaring) · [Reading and writing](#reading-and-writing) · [Errors](#errors) · [Types](#types)
- [Arrays, nested structs, unions](#arrays-nested-structs-unions) · [Dates, times, zones](#dates-times-zones)
- [Class settings](#class-settings) · [Validation](#validation) · [JSON](#json) · [Introspection](#introspection)
- [Type signatures](#type-signatures) · [Custom types](#custom-types) · [Exceptions](#exceptions)

## Declaring

```
required :name, :type, **options     # must be present
optional :name, :type, **options     # may be missing
field    :name, :type, **options     # optional unless required: true
```

`name` is a Symbol or String. `type` is a registered name (`:string`), a `FieldStruct::Base` subclass, or a type class.
Declaring a name twice replaces the first. Reserved names (`errors`, `attributes`, `to_h`, `hash`, `class`, ...) raise
`ArgumentError` at declaration. Every declaration problem raises while the class body runs, never at first use.

<!-- doctest -->
```ruby
require 'field_struct'

class Specimen < FieldStruct::Base
  required :name,  :string, description: 'Display label'
  optional :height,   :integer, in: 0..150
  optional :role,  :symbol, enum: %i[wild bred], default: :bred
  field    :email, :email, required: true
  optional :seen,  :time, default: -> { Time.at(0).utc }   # a callable default runs per instance
  optional :token, :string, sensitive: true
end

specimen = Specimen.new(name: 'Ivy', email: 'curator@example.org')
specimen.role         # => :bred
specimen.height          # => nil
specimen.valid?       # => true
Specimen.attribute_names   # => [:name, :height, :role, :email, :seen, :token]
```

### Options valid on every type

| Option | Values | Notes |
|---|---|---|
| `required:` | `true` / `false` | `required` and `optional` force it |
| `default:` | literal or callable | `nil` means no default. A callable (anything that responds to `call`) runs once per instance |
| `coercion_policy:` | `:keep_raw` `:replace` `:raise` | overrides the class policy for this field |
| `description:` / `desc:` | String | passing both raises |
| `rbs_type:` | non-blank String | replaces the derived RBS type |
| `sensitive:` | `true` / `false` only | masks the value in `inspect` as `[FILTERED]` |

A key that no type declares is a pass-through option: it's stored in `field.options` and does nothing at runtime, so
exporters can read it (`optional :id, :integer, avro_doc: 'the id'`). A key that some *other* type declares raises at
declaration (`round:` on a string field: `round: option does not apply to String fields. It applies to: Float, BigDecimal.`).

## Reading and writing

<!-- doctest -->
```ruby
require 'field_struct'

class Quadrat < FieldStruct::Base
  required :row, :integer
  required :col, :integer
end

quadrat = Quadrat.new('row' => '3', col: 4.9)    # String or Symbol keys; values are coerced
quadrat.row                                  # => 3
quadrat.col                                  # => 4
quadrat.attributes                         # => {row: 3, col: 4}
quadrat.to_h == quadrat.attributes           # => true
quadrat.row = '10'                           # writers coerce too
quadrat.row                                  # => 10
quadrat.assign_attributes(row: 1, col: 2)      # bulk, same pipeline
quadrat.with(col: 9).col                       # => 9
quadrat.col                                  # => 2
quadrat == Quadrat.new(row: 1, col: 2)           # => true
quadrat.deconstruct_keys([:row])             # => {row: 1}
quadrat.deconstruct                        # => [1, 2]
Quadrat.new(nil).attributes                # => {row: nil, col: nil}
```

`new` takes a Hash, or anything that responds to `to_hash`. Anything else raises
`ArgumentError: Quadrat.new expects a Hash (or an object responding to #to_hash), got Array`.
Pattern matching works: `case quadrat in {row:, col:} ...`.

## Errors

`obj.errors` is a `FieldStruct::Errors`. It records, it never raises.

| Message | When |
|---|---|
| `"is required"` | a required field is missing (nil, blank string, empty array) |
| `"is invalid"` | `format:`, `enum:` or `in:` failed, or a nested struct inside is invalid |
| `"could not be coerced: <reason>"` | the type could not read the value |
| anything you add | from `validate` |

<!-- doctest -->
```ruby
require 'field_struct'

class Seedling < FieldStruct::Base
  required :batch, :string, format: /\A[A-Z]{3}-\d+\z/
  optional :trays, :integer
end

tray = Seedling.new(batch: 'abc', trays: 'lots')
tray.valid?                       # => false
tray.errors[:batch]                 # => ["is invalid"]
tray.errors[:trays].first.start_with?('could not be coerced')   # => true
tray.errors.full_messages.first   # => "Batch is invalid"
tray.errors.empty?                # => false
tray.errors.add(:base, 'Something else')
tray.errors.full_messages.last    # => "Something else"
tray.errors.clear(:batch)
tray.errors[:batch]                 # => []
tray.batch = 'ABC-1'                # assigning re-checks the field
tray.errors[:batch]                 # => []
```

Messages never contain the offending value, only its class. Errors are per assignment: assigning again clears the
field's old messages and runs the checks again. `batch: nil` on a required field gives `"is required"`; the value is nil.

### What a failed coercion does (`coercion_policy`)

| Policy | Behaviour |
|---|---|
| `:keep_raw` (default) | the raw input is stored, one `could not be coerced` message is recorded |
| `:replace` | the field becomes `nil`, the message is recorded |
| `:raise` | `FieldStruct::CoercionError` (with `field_name` and `original`) |

<!-- doctest -->
```ruby
require 'field_struct'

class Forgiving < FieldStruct::Base
  optional :a, :integer
  optional :b, :integer, coercion_policy: :replace
  optional :c, :integer, coercion_policy: :raise
end

l = Forgiving.new(a: 'x', b: 'y')
l.a   # => "x"
l.b   # => nil
begin
  Forgiving.new(c: 'z')
rescue FieldStruct::CoercionError => e
  e.field_name   # => :c
end
```

## Types

Every type accepts `nil` and returns `nil`. "Missing" is what `required` rejects.

### Strings

| Type | Coerces | Missing | Lot |
|---|---|---|---|
| `:string` | any value via `to_s` | nil, blank | `String` |
| `:immutable_string` | as `:string` | nil, blank | frozen copy |
| `:uuid` `:url` `:email` | as `:string`, and checks a default `format:` | nil, blank | `String` |
| `:binary` | any value via `to_s`, bytes as ASCII-8BIT | nil, empty | `String` |

Options: `format:` (a Regexp, or a preset name for `:uuid` `:url` `:email`), `enum:` (Array), `strict:` (`true` accepts
only String, Symbol, Integer or `to_str` objects).

| Type | Presets (`format: :name`) | Default |
|---|---|---|
| `:uuid` | `any_version` `v4` `v7` | `any_version` |
| `:url` | `http` `https_only` `any_scheme` | `http` |
| `:email` | `permissive` `default` `strict` | `default` |

<!-- doctest -->
```ruby
require 'field_struct'

class Marker < FieldStruct::Base
  optional :id,    :uuid, format: :v4
  optional :href,  :url, format: :https_only
  optional :mail,  :email, format: :strict
  optional :slug,  :string, enum: %w[a b]
  optional :note,  :string, strict: true
  optional :frozen, :immutable_string
end

Marker.new(slug: 'a').valid?                 # => true
Marker.new(slug: 'z').errors[:slug]          # => ["is invalid"]
Marker.new(href: 'http://x.io').valid?       # => false
Marker.new(note: 1.5).valid?                 # => false
Marker.new(frozen: +'x').frozen.frozen?      # => true
Marker.new(slug: 12).slug                    # => "12"
```

`format:` is matched against the String form (`\A` and `\z` anchors are yours to write). An explicit
`enum:`/`format:` check is skipped for `nil`.

### Symbols

`:symbol` turns a String into a Symbol and keeps Symbols. Anything else is a coercion failure. `enum:` is checked after
coercion, so `'wild'` matches `enum: %i[wild bred]`.

### Numbers

| Type | Reads | Options |
|---|---|---|
| `:integer` | Integer; String in `base:` (default 10; `"010"` is 10, `"1_000"` is 1000); Float and Rational truncate toward zero | `in:` (Range or Array), `base:` (2..36), `strict:` |
| `:float` | Float; numeric Strings (`"1e3"`, `".5"`); anything `Float()` takes | `round:` (digits, half up), `in:` |
| `:decimal` / `:big_decimal` | BigDecimal; Float via 15 digits; numeric Strings | `round:`, `in:` |

NaN and the infinities are always refused. `strict: true` on `:integer` accepts only whole numbers (`12.0` yes,
`12.7` no); Strings follow the normal rules.

<!-- doctest -->
```ruby
require 'field_struct'
require 'bigdecimal'

class Gauge < FieldStruct::Base
  optional :count, :integer, base: 16
  optional :whole, :integer, strict: true
  optional :temp,  :float, round: 1, in: -90.0..60.0
  optional :yield_kg, :decimal, round: 2
end

m = Gauge.new(count: '1A', whole: 12.0, temp: '21.46', yield_kg: '12.345')
m.count    # => 26
m.whole    # => 12
m.temp     # => 21.5
m.yield_kg    # => BigDecimal('12.35')
Gauge.new(whole: 12.7).valid?   # => false
Gauge.new(temp: 100).errors[:temp]   # => ["is invalid"]
Gauge.new(count: '12.5').valid?   # => false
```

### Booleans

`true` / `false`, the integers `1` / `0`, and the Strings `true false 1 0` (any case, no trimming). `values:` swaps in
your own String vocabulary: a Hash `{truthy: [...], falsy: [...]}` or a preset (`:english_yes_no` = `:english`
= `true yes y on 1` / `false no n off 0, `:numeric` = `1` / `0`). The vocabulary only applies to Strings.

<!-- doctest -->
```ruby
require 'field_struct'

class Switches < FieldStruct::Base
  optional :plain,   :boolean
  optional :english, :boolean, values: :english
  optional :custom,  :boolean, values: {truthy: %w[si], falsy: %w[no]}
end

Switches.new(plain: 'TRUE').plain         # => true
Switches.new(english: 'Yes').english      # => true
Switches.new(custom: 'si').custom         # => true
Switches.new(plain: 'yes').valid?         # => false
```

### Any value

`:value` stores whatever it's given, untouched. Only nil is missing.

## Arrays, nested structs, unions

### Arrays

`:array` needs `of:` (a type name, a struct class or a type class). Elements are coerced one by one; `nil` elements stay
`nil`. One bad element fails the whole array, and the message names the indexes (never the values). `[]` is missing.
`element:` passes options to every element.

<!-- doctest -->
```ruby
require 'field_struct'

class Rack < FieldStruct::Base
  required :ids, :array, of: :integer, element: {in: 1..99}
  optional :emails, :array, of: :email
end

Rack.new(ids: %w[1 2 3]).ids         # => [1, 2, 3]
Rack.new(ids: []).errors[:ids]       # => ["is required"]
Rack.new(ids: [1, 'x', 'y']).errors[:ids].first   # => "could not be coerced: elements at index 1, 2 (index 1 shown): Integer fields expect a base-10 integer, got a String that is not one"
Rack.new(ids: [1, 500]).errors[:ids]   # => ["element at index 1 is invalid"]
Rack.new(ids: 'nope').valid?         # => false
```

`of:` must be given (`of: is required for Array fields`). An array of arrays is not supported.

### Nested structs

A field typed with a struct class takes an instance or a Hash. Passing a Hash builds the struct, even an invalid one;
the parent field then reads `"is invalid"`.

<!-- doctest -->
```ruby
require 'field_struct'

class Bed < FieldStruct::Base
  required :habitat, :string
  optional :plot_no,  :string
end

class Gardener < FieldStruct::Base
  required :name, :string
  optional :border, Bed
  optional :rotation, :array, of: Bed
end

gardener = Gardener.new(name: 'Ivy', border: {habitat: 'Fen'}, rotation: [{habitat: 'Heath'}, Bed.new(habitat: 'Moor')])
gardener.border.class          # => Bed
gardener.rotation.map(&:habitat)   # => ["Heath", "Moor"]
Gardener.new(name: 'Ivy', border: {plot_no: '1'}).errors[:border]   # => ["is invalid"]
Gardener.new(name: 'Ivy', border: 5).errors[:border].first.start_with?('could not be coerced')   # => true
```

Validity is computed on assignment. Changing a nested object afterwards doesn't refresh the parent: re-assign it, or use
`with`.

### Unions

`:union` takes `of: [...]` (two or more registered names or struct classes). Members are tried in order and the first
that accepts wins, so order matters. A union can't hold an `:array` bred.

<!-- doctest -->
```ruby
require 'field_struct'

class Survey < FieldStruct::Base
  optional :ref, :union, of: %i[integer string]
  optional :tag, :union, of: %i[string integer]
  optional :flag, :union, of: %i[integer boolean]
end

Survey.new(ref: '42').ref   # => 42
Survey.new(tag: '42').tag   # => "42"
Survey.new(flag: 'maybe').valid?   # => false
```

## Dates, times, zones

| Type | Reads | Lot |
|---|---|---|
| `:date` | String, Date, DateTime, Time | `Date` (a Time or DateTime keeps its own wall-clock day) |
| `:time` | String, Time, DateTime, Date | `Time` |
| `:datetime` | String, DateTime, Time, Date | `DateTime` |

Without `format:`, a String must name a whole day (year, month and day) that exists. Integers are refused. `format:`
is either a strptime String or a preset (`:iso8601` is RFC 3339, parsed by the gem itself):

| Preset | `:date` | `:time` / `:datetime` |
|---|---|---|
| `iso8601` | `2026-07-03` | `2026-07-03T10:30:00-06:00`, `...Z`, fractions allowed |
| `us` | `%m/%d/%Y` | |
| `eu` | `%d/%m/%Y` | |
| `rfc2822` | | `%a, %d %b %Y %H:%M:%S %z` |
| `db` | | `%Y-%m-%d %H:%M:%S` |

A declared format must match the whole string, and it is also what `as_json` writes. `in:` takes a Range or an Array.
`zone:` says which zone a zone-less string means: `"UTC"`, an offset like `"-06:00"`, or an IANA name
(`"America/Denver"`). It never overrides an offset the input carries.

<!-- doctest -->
```ruby
require 'field_struct'

class Visit < FieldStruct::Base
  optional :day,    :date, format: :us, in: Date.new(2026, 1, 1)..Date.new(2026, 12, 31)
  optional :starts, :time, zone: 'America/Denver'
  optional :ends,   :datetime, format: :iso8601
end

shift = Visit.new(day: '07/03/2026', starts: '2026-07-01 10:00', ends: '2026-07-01T10:00:00-06:00')
shift.day.iso8601                          # => "2026-07-03"
shift.starts.utc_offset                    # => -21600
Visit.new(starts: '2026-01-15 10:00').starts.utc_offset   # => -25200
shift.as_json[:day]                        # => "07/03/2026"
shift.as_json[:ends]                       # => "2026-07-01T10:00:00-06:00"
Visit.new(day: '2026-02-30').valid?        # => false
# Denver skips 02:30 on 2026-03-08
Visit.new(starts: '2026-03-08 02:30').valid?   # => false
```

The result is a plain `Time` or `DateTime` with the right offset; it doesn't remember the zone. The zone database
(`tzinfo`) is loaded only when a field names an IANA zone.

## Class settings

| Macro | Values | Default |
|---|---|---|
| `coercion_policy` | `:keep_raw` `:replace` `:raise` | `:keep_raw` |
| `unknown_attributes` | `:ignore` `:raise` | `:ignore` |
| `immutable!` | setters raise `ImmutableError` after `new` | off |
| `frozen!` | instances are frozen at the end of `new` | off |
| `serialize :format, field: 'name'` | maps field names for a format (see JSON) | none |
| `validate :method, ...` / `validate { |record| ... }` | cross-field checks (see Validation) | none |

Rules are inherited; a subclass can change its own without touching the parent. `immutable?` and
`frozen_on_construct?` read the flags.

<!-- doctest -->
```ruby
require 'field_struct'

class Rules < FieldStruct::Base
  coercion_policy :replace
  unknown_attributes :raise
  immutable!
  required :level, :integer
end

Rules.new(level: 'x').level    # => nil
begin
  Rules.new(level: 1, extra: 2)
rescue FieldStruct::UnknownAttributeError => e
  e.keys   # => [:extra]
end
begin
  Rules.new(level: 1).level = 2
rescue FieldStruct::ImmutableError => e
  e.message   # => "Rules is immutable; cannot reassign level"
end
Rules.new(level: 1).with(level: 2).level   # => 2
```

## Validation

`validate` registers methods (called with no arguments) or a block (called with the record). Validators run after the
per-field checks, once at the end of `new` and `with`, and again on every `valid?`. Before each run `errors[:base]` is
cleared, so cross-field messages belong under `:base`. A validator that adds to a named field has to clean up after
itself.

<!-- doctest -->
```ruby
require 'field_struct'

class Bracket < FieldStruct::Base
  required :low,  :integer
  required :high, :integer
  validate :ordered
  validate { |span| span.errors.add(:base, 'both are zero') if span.low == 0 && span.high == 0 }

  def ordered
    errors.add(:base, 'high must be above low') if low && high && high <= low
  end
end

Bracket.new(low: 3, high: 1).errors[:base]   # => ["high must be above low"]
Bracket.new(low: 0, high: 0).errors[:base]   # => ["high must be above low", "both are zero"]
Bracket.new(low: 1, high: 2).valid?          # => true
span = Bracket.new(low: 1, high: 2)
span.high = 0
span.valid?                               # => false
```

A validator must cope with nil fields, because the record may be invalid. A subclass gets a copy of its parent's
validators and adds its own.

## JSON

`as_json` returns a Hash with Symbol keys, every field present. `to_json` is `Oj.dump(as_json, mode: :compat)`.
`from_json(string)` parses with Oj (fractions and exponents arrive as BigDecimal) and builds through `new`, so every
rule above applies.

`serialize :json, internal_name: 'external_name'` renames keys in both directions, recursively through nested structs
and arrays of structs. Canonical names are also accepted on input.

<!-- doctest -->
```ruby
require 'field_struct'

class Dispatch < FieldStruct::Base
  required :species, :string
  optional :cost, :decimal
  optional :sent_at, :datetime, format: :iso8601
  serialize :json, sent_at: 'sentAt'
end

dispatch = Dispatch.from_json('{"species":"Hi","cost":2.5,"sentAt":"2026-03-04T05:06:07Z"}')
dispatch.cost                  # => BigDecimal('2.5')
dispatch.sent_at.year          # => 2026
dispatch.as_json               # => {species: "Hi", cost: "2.5", sentAt: "2026-03-04T05:06:07Z"}
Dispatch.from_json(dispatch.to_json) == dispatch   # => true

begin
  Dispatch.from_json('[1]')
rescue ArgumentError => e
  e.message   # => "from_json expects a JSON object root, got Array"
end

begin
  Dispatch.from_json('{oops')
rescue EncodingError => e
  e.message.start_with?('from_json could not parse its input as JSON')   # => true
end
```

Decimals go out as strings so no digits are lost. Dates and times go out with the field's `format:`. A `:value` field
round-trips only if its content is plain JSON.

## Introspection

<!-- doctest -->
```ruby
require 'field_struct'

class Chore < FieldStruct::Base
  required :species, :string, description: 'What to do'
  optional :done, :boolean
  optional :tags, :array, of: :string
end

puts Chore.describe
Chore.metadata[:species].required?          # => true
Chore.metadata[:species].type               # => FieldStruct::Types::String
Chore.metadata[:species].description        # => "What to do"
Chore.metadata[:tags].options[:of_type]   # => FieldStruct::Types::String
Chore.metadata.names                      # => [:species, :done, :tags]
Chore.metadata.to_h[:done][:required]     # => false
Chore.new(species: 'x').inspect             # => '#<Chore species: "x", done: nil, tags: nil>'
```

`FieldStruct::Introspection.properties(klass, serialization: :json)` walks a struct for code that exports it to
another schema language (JSON Schema, Avro, Protobuf); it returns `Property` objects with `field`, `key` and a `node`
(`ScalarNode`, `ArrayNode`, `UnionNode` or `StructNode`). `FieldStruct.use_alias!(:FS)` makes `FS` mean `FieldStruct`
and switches every `inspect` to it.

## Type signatures

The gem ships `sig/field_struct.rbs`. For your own models:

<!-- doctest -->
```ruby
require 'field_struct'

class Plant < FieldStruct::Base
  required :species, :string
  optional :leaves, :integer
  optional :tags, :array, of: :string
  optional :rating, :union, of: %i[integer float]
end

puts FieldStruct::RBS.generate(Plant).lines.drop(3).first(6)
FieldStruct::RBS.type_for(Plant.metadata[:leaves])                   # => "::Integer?"
FieldStruct::RBS.type_for(Plant.metadata[:species])                   # => "::String"
FieldStruct::RBS.type_for(Plant.metadata[:species], nullable: true)   # => "::String?"
FieldStruct::RBS.type_for(Plant.metadata[:rating])                  # => "(::Integer | ::Float)?"
```

Readers of a required field have no `?`; writers always accept `nil`. The types describe a *valid* instance: an invalid one
can hold other values, so check `valid?`. Override a field with `rbs_type: '::Pathname'`, or give a custom type an
`rbs_type` method. Scalar array elements are nullable (`::Array[::String?]`).

`FieldStruct::Scaffold.from_json(sample)` writes the model class for a JSON sample (a JSON String or parsed data).

## Custom types

Subclass `FieldStruct::Types::Base`, implement `coerce(value, **options)` and `ruby_type`; optionally `missing?`,
`own_option_schema` (the options your type takes) and `rbs_type`. Raise `ArgumentError`, `TypeError` or `RangeError` from
`coerce` to mean "can't read this". Register it by name in a registry. A module that defines `field_types` returning
a registry makes the names available to every struct inside it, falling back to the built-in types.

<!-- doctest -->
```ruby
require 'field_struct'

class Moisture < FieldStruct::Types::Base
  def coerce(value, **)
    return nil if value.nil?

    number = Float(value.to_s.delete_suffix('%'))
    raise ArgumentError, 'Moisture fields expect 0 to 100' unless (0..100).cover?(number)

    number
  end

  def ruby_type = Float
  def rbs_type = '::Float'
end

module Seedbank
  def self.field_types
    @field_types ||= FieldStruct.new_registry { register :moisture, Moisture }
  end

  class Lot < FieldStruct::Base
    required :humidity, :moisture
  end
end

Seedbank::Lot.new(humidity: '42%').humidity            # => 42.0
Seedbank::Lot.new(humidity: '420%').valid?          # => false
FieldStruct.types.key?(:moisture)                # => false
```

`FieldStruct.new_registry(parent = FieldStruct.types, &block)` builds a registry; `register(:name, SomeClass)` adds a
type and `register(:alias, :existing)` aliases one. Lookup of an unknown name raises `KeyError`.

## Exceptions

```
StandardError
  FieldStruct::Error
    FieldStruct::CoercionError         #field_name, #original
    FieldStruct::ImmutableError
    FieldStruct::UnknownAttributeError #keys
```

`from_json` raises Ruby's `EncodingError` for malformed JSON and `ArgumentError` for a non-object root. Declaration
mistakes raise `ArgumentError` (or `KeyError` for an unknown type name) while the class body runs.
