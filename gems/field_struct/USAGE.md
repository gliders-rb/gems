# field_struct usage reference

A dense, example-first reference. Read it once; every example runs.

- [Declaring](#declaring) · [Reading and writing](#reading-and-writing) · [Errors](#errors) · [Types](#types)
- [Arrays, maps, nested structs, unions](#arrays-maps-nested-structs-unions) · [Dates, times, zones](#dates-times-zones)
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

```ruby run
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

A key that some *other* type declares raises at declaration (`round:` on a string field: `round: option does not apply
to String fields. It applies to: Float, BigDecimal.`). A key nobody declares raises too, with a suggestion when one is
close, so a typo like `requird: true` fails at load instead of doing nothing:

```ruby run
class Ledger < FieldStruct::Base
  required :folio, :integer
end

begin
  Ledger.optional :spine, :string, requird: true
rescue ArgumentError => e
  e.message   # => "unknown option requird: on Ledger#spine (did you mean required:?)"
end
```

An exporter or app that reads its own key registers it first with `FieldStruct.register_option(name, type:, owner:)`.
After that the key is accepted on any field, its value is checked against `type:` (`nil` is always fine), and it's
stored in `field.options` untouched. It does nothing at runtime. The adapters register theirs when you require them
(`avro:`, `proto:`, `json_schema:`), and using one before its adapter loads says which file to require.

```ruby run
FieldStruct.register_option(:catalog, type: Hash, owner: 'ledger_app')   # => :catalog

class Ledger
  optional :clasp, :string, catalog: {shelf: 'B4'}
end

Ledger.metadata[:clasp].options                       # => {catalog: {shelf: "B4"}}
FieldStruct.registered_options[:catalog].owner        # => "ledger_app"
```

Registering the same name, type and owner again does nothing; anything else that already has the name, a universal
option or a built-in type's option raises. `FieldStruct.registered_options` lists every registration in order, each a
`FieldStruct::RegisteredOption` with `name`, `type` (an Array of classes) and `owner`.

## Reading and writing

```ruby run
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
quadrat.invalid?                             # => false
quadrat.deconstruct_keys([:row])             # => {row: 1}
quadrat.deconstruct                        # => [1, 2]
Quadrat.new(nil).attributes                # => {row: nil, col: nil}
```

`new` takes a Hash, or anything that responds to `to_hash`. Anything else raises
`ArgumentError: Quadrat.new expects a Hash (or an object responding to #to_hash), got Array`.
Pattern matching works: `case quadrat in {row:, col:} ...`.

`given_fields` lists the fields the caller gave, in declaration order, so "sent as null" and "not sent" stay apart
(what a PATCH body needs). Defaults and unknown keys never count:

```ruby run
class Transect < FieldStruct::Base
  required :site, :string
  optional :bearing, :integer, default: 0
  optional :remark, :string
end

walk = Transect.new(site: 'ridge', remark: nil)
walk.given_fields                         # => [:site, :remark]
walk.with(bearing: 90).given_fields       # => [:site, :bearing, :remark]
```

## Errors

`obj.errors` is a `FieldStruct::Errors`. It records, it never raises.

| Message | When |
|---|---|
| `"is required"` | a required field is missing (nil, blank string, empty array) |
| `"is invalid"` | `format:`, `enum:` or `in:` failed, or a nested struct inside is invalid |
| `"could not be coerced: <reason>"` | the type could not read the value |
| anything you add | from `validate` |

```ruby run
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
tray.errors.messages.keys         # => [:trays, :base]
```

`errors.messages` is a Hash of field to messages. `errors.paths` keys the same messages by where they happened, so a
nested struct's message lands on its own field instead of the parent's `"is invalid"`:

```ruby run
require 'field_struct'

class Bed < FieldStruct::Base
  required :rows, :integer
end

class Plot < FieldStruct::Base
  required :label, :string
  optional :bed, Bed
end

plot = Plot.new(label: 'north', bed: { rows: nil })
plot.errors[:bed]     # => ["is invalid"]
plot.errors.paths     # => {"bed.rows" => ["is required"]}
```

`errors.freeze` freezes the messages too, so `add` and `clear` raise `FrozenError`, and `valid?` then reads them as
they are instead of running the validators. A `dup` gets errors it can change again.

Messages never contain the offending value, only its class. Errors are per assignment: assigning again clears the
field's old messages and runs the checks again. `batch: nil` on a required field gives `"is required"`; the value is nil.

### What a failed coercion does (`coercion_policy`)

| Policy | Behaviour |
|---|---|
| `:keep_raw` (default) | the raw input is stored, one `could not be coerced` message is recorded |
| `:replace` | the field becomes `nil`, the message is recorded |
| `:raise` | `FieldStruct::CoercionError` (with `field_name` and `original`) |

```ruby run
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

An option on a type that doesn't take it raises at declaration and lists the types that do:

<!-- generated: option-types -->
| Option | Types |
|---|---|
| `format:` | `:string`, `:immutable_string`, `:date`, `:time`, `:datetime`, `:uuid`, `:url`, `:email`, `:binary` |
| `enum:` | `:string`, `:immutable_string`, `:symbol`, `:uuid`, `:url`, `:email`, `:binary` |
| `strict:` | `:string`, `:immutable_string`, `:integer`, `:uuid`, `:url`, `:email`, `:binary` |
| `length:` | `:string`, `:immutable_string`, `:uuid`, `:url`, `:email`, `:binary` |
| `in:` | `:integer`, `:float`, `:big_decimal`, `:decimal`, `:date`, `:time`, `:datetime` |
| `base:` | `:integer` |
| `round:` | `:float`, `:big_decimal`, `:decimal` |
| `json:` | `:big_decimal`, `:decimal` |
| `values:` | `:boolean` |
| `zone:` | `:time`, `:datetime` |
| `of:` | `:array`, `:hash`, `:union` |
| `element:` | `:array`, `:hash` |
| `max_items:` | `:array` |
| `discriminator:` | `:union` |
<!-- end generated -->

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

```ruby run
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
| `:decimal` / `:big_decimal` | BigDecimal; Float via 15 digits; numeric Strings | `round:`, `in:`, `json:` |

NaN and the infinities are always refused. `strict: true` on `:integer` accepts only whole numbers (`12.0` yes,
`12.7` no); Strings follow the normal rules.

```ruby run
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

```ruby run
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

## Arrays, maps, nested structs, unions

Fields that hold other values: lists, maps with String keys, other structs, and one of several types.

### Arrays

`:array` needs `of:` (a type name, a struct class or a type class). Elements are coerced one by one; `nil` elements stay
`nil`. One bad element fails the whole array, and the message names the indexes (never the values). `[]` is missing.
`element:` passes options to every element.

```ruby run
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

`of:` must be given (`of: is required for Array fields`). An array of arrays is not supported. `max_items: N` caps the
length: a longer array gets the field error `has too many items (maximum is N)`.

### Maps

`:hash` is a map with String keys: `of:` names the value type and `element:` passes options to every value, as for
arrays. Symbol keys become Strings; any other key class fails the whole map. `{}` is missing. Messages say how many
entries failed, never which key, since a key is input. A map of structs builds each value, and `errors.paths` names
the entry with its key.

```ruby run
require 'field_struct'

class Buoy < FieldStruct::Base
  required :metres, :float
end

class Mooring < FieldStruct::Base
  optional :depths, :hash, of: :integer, element: {in: 0..90}
  optional :buoys, :hash, of: Buoy
end

Mooring.new(depths: {north: '12', 'south' => 7}).depths   # => {"north" => 12, "south" => 7}
Mooring.new(depths: {north: 200}).errors[:depths]       # => ["1 entry is invalid"]
Mooring.new(depths: {1 => 3}).errors[:depths].first     # => "could not be coerced: hash keys must be Strings or Symbols, got Integer"
Mooring.new(buoys: {'outer' => {}}).errors.paths        # => {"buoys{\"outer\"}.metres" => ["is required"]}
```

### Mirrors

`mirror!` makes a struct a view other objects can be read into. A field of a mirror type (or an array or map of one)
takes any object besides a Hash or an instance: the mirror calls one public reader per declared field, by field name,
and builds through `new`, so only declared fields are read and everything is coerced as usual. A source missing a
reader always raises, whatever the policy or default. `mirror?` tells you whether a class (or an ancestor) is one.

```ruby run
require 'field_struct'

class GaugeView < FieldStruct::Base
  mirror!
  required :celsius, :float
end

class SiteView < FieldStruct::Base
  mirror!
  required :code, :string
  optional :gauges, :array, of: GaugeView, max_items: 2
end

class Report < FieldStruct::Base
  required :site, SiteView
end

Gauge = Struct.new(:celsius, :serial)
Site = Struct.new(:code, :gauges, :keeper_phone)

report = Report.new(site: Site.new('PK-7', [Gauge.new('4.5', 'g1')], '555'))
SiteView.mirror?                    # => true
report.site.as_json                 # => {code: "PK-7", gauges: [{celsius: 4.5}]}
Report.new(site: Site.new('PK-8', [Gauge.new(1, 'a')] * 3, nil)).site.errors[:gauges]   # => ["has too many items (maximum is 2)"]

begin
  Report.new(site: Gauge.new(2.0, 'g2'))
rescue ArgumentError => e
  e.message   # => "SiteView mirrors Gauge, but Gauge has no public readers for :code, :gauges"
end
```

An array of mirrors also takes a collection that isn't an Array. One whose `loaded?` is `true` is read with `to_a`.
Anything else that answers `first` (a lazy relation, say) needs `max_items:` and is read with `first(max_items + 1)`,
so going over is an error, never a silent cut. Without `max_items:` it raises `set max_items: on Report#gauges, or
load the relation yourself`. A union member never reads; a union still takes a Hash or an instance.

### Nested structs

A field typed with a struct class takes an instance or a Hash. Passing a Hash builds the struct, even an invalid one;
the parent field then reads `"is invalid"`.

```ruby run
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

```ruby run
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

```ruby run
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
| `json_omit` | `:none` `:unset` (see JSON) | `:none` |
| `immutable!` | setters raise `ImmutableError` after `new` | off |
| `frozen!` | instances are frozen at the end of `new` | off |
| `mirror!` | fields of this type read other objects into it (see Mirrors); read with `mirror?` | off |
| `serialize :format, field: 'name'` | maps field names for a format (see JSON) | none |
| `validate :method, ...` / `validate { |record| ... }` | cross-field checks (see Validation) | none |

Rules are inherited; a subclass can change its own without touching the parent. `immutable?` and
`frozen_on_construct?` read the flags.

```ruby run
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

```ruby run
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

`as_json` returns a Hash with Symbol keys, every field present (unless the class says `json_omit :unset`, below). `to_json` is `Oj.dump(as_json, mode: :compat)`, except
that decimals go out as JSON numbers.
`from_json(string)` parses with Oj (fractions and exponents arrive as BigDecimal) and builds through `new`, so every
rule above applies.

`serialize :json, internal_name: 'external_name'` renames keys in both directions, recursively through nested structs
and arrays of structs. Canonical names are also accepted on input.

```ruby run
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
dispatch.to_json               # => "{\"species\":\"Hi\",\"cost\":2.5,\"sentAt\":\"2026-03-04T05:06:07Z\"}"
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

`to_json` writes a decimal as a JSON number with every digit (`BigDecimal('12.50')` is `12.5`), in arrays, maps,
nested structs and `:value` fields too. `as_json` keeps it a String, so another encoder that writes the Hash gets
strings. A field declared `json: :string` (or `element: {json: :string}` on an array or map of decimals) keeps the
string in `to_json` too, for values that must survive JavaScript's float parsing; `json:` takes `:number` or `:string`.
A `Types::BigDecimal` subclass can change the default for all its fields by answering `json_default` with `:string`.
`from_json` reads either form back to the same BigDecimal. Dates and times go out with the field's `format:`. A `:value` field
round-trips only if its content is plain JSON.

A `:value` field holding some other object writes that object's own `as_json`. Pass `describe_foreign: true` to write a
short description instead (`"#<Kiln id=12>"`); only the object's `class` and `id` are read.

```ruby run
require 'field_struct'

class Kiln
  attr_reader :id
  def initialize(id) = @id = id
  def as_json(*) = { 'id' => id, 'firing_log' => ['cone 6'] }
end

class Shift < FieldStruct::Base
  optional :kiln, :value
end

shift = Shift.new(kiln: Kiln.new(12))
shift.as_json                          # => {kiln: {"id" => 12, "firing_log" => ["cone 6"]}}
shift.as_json(describe_foreign: true)  # => {kiln: "#<Kiln id=12>"}
```

`json_omit :unset` leaves a field out of `as_json` and `to_json` when the caller didn't give it and it's `nil`.
Defaults are still written, and so is a `nil` the caller gave. A nested struct follows its own class's setting.

```ruby run
require 'field_struct'

class Sounding < FieldStruct::Base
  json_omit :unset
  optional :station, :string
  optional :tethered, :boolean, default: true
  optional :burst_m, :integer
end

Sounding.json_omit                                   # => :unset
Sounding.new(station: 'Ridge').as_json               # => {station: "Ridge", tethered: true}
Sounding.new(station: 'Ridge', burst_m: nil).as_json # => {station: "Ridge", tethered: true, burst_m: nil}
```

For an update (PATCH) body, `Klass.partial` gives a sibling class, `Klass::Partial`, built on the first call: the same
fields and mappings, every field optional with no default, and `json_omit :unset`, so its JSON holds exactly what the
caller sent. Type checks and field options still apply; cross-field `validate` rules and methods you defined on
`Klass` (reader overrides too) don't carry over. It is not a subclass of `Klass`.

```ruby run
require 'field_struct'

class Tower < FieldStruct::Base
  required :callsign, :string
  required :height_m, :integer, default: 30
  serialize :json, height_m: 'heightM'
end

patch = Tower.partial.new(height_m: '45')
patch.valid?                    # => true
patch.as_json                   # => {heightM: 45}
Tower.partial.equal?(Tower::Partial)   # => true
patch.is_a?(Tower)              # => false
```

## Introspection

```ruby run
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
Chore.metadata.each.map(&:name)           # => [:species, :done, :tags]
Chore.metadata[:done].nullable?             # => false
Chore.metadata[:done].sensitive?            # => false
Chore.metadata[:done].type_instance.class   # => FieldStruct::Types::Boolean
Chore.metadata.serializations             # => {}
Chore.metadata.reverse_serialization(:json)   # => {}
Chore.validators                          # => []
```

`metadata.serializations` holds the key mappings declared with `serialize`, and `reverse_serialization(:json)` maps
an external key back to its field. `validators` lists the blocks given to `validate`, inherited as a copy.

For Rails helpers a struct answers `model_name` and `to_model` (itself); it isn't a form object and has no
persistence methods:

```ruby run
require 'field_struct'

class Seedling < FieldStruct::Base
  optional :trays, :integer
end

Seedling.model_name.singular       # => "seedling"
Seedling.model_name.plural         # => "seedlings"
Seedling.new.model_name.singular   # => "seedling"
Seedling.model_name.param_key      # => "seedling"
seedling = Seedling.new
seedling.to_model.equal?(seedling)   # => true
```

`param_key` is the key `form_with model: seedling, url: '/seedlings'` nests the fields under (`seedling[trays]`). It's
the last segment only, so `Nursery::Seedling` is `"seedling"` too; pass `scope:` when two classes end the same way.
Give `form_with` a `url:`, since a struct has no routes or `persisted?`.

`FieldStruct::Introspection.properties(klass, serialization: :json)` walks a struct for code that exports it to
another schema language (JSON Schema, Avro, Protobuf); it returns `Property` objects with `field`, `key` and a `node`
(`ScalarNode`, `ArrayNode`, `MapNode`, `UnionNode` or `StructNode`; a `UnionNode` lists its `members`, and an
`ArrayNode` or `MapNode` its `element`).
`FieldStruct::Introspection.named?(klass)` says whether a class can name a definition (false for anonymous classes).
`FieldStruct.use_alias!(:FS)` makes `FS` mean `FieldStruct` and switches every `inspect` to it; `FieldStruct.inspect_namespace`
returns the prefix in use (`"FieldStruct"` until then).

## Type signatures

The gem ships `sig/field_struct.rbs`. For your own models:

```ruby run
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

```ruby run
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
type and `register(:alias, :existing)` aliases one. `registry.lookup(:moisture)` returns the class, and raises
`KeyError` for an unknown name; `registry.type_classes` lists every class it resolves, its own first.

A type's options are its `option_schema` (built from `own_option_schema`, inherited keys first). Two class-level hooks
run at declaration: `resolve_options(options, **)` returns the options to store (override it to
turn a preset Symbol into a value, or to reject a bad one), and `resolve_format(format)` returns a `format:` unchanged,
raising for a Symbol when the type has no presets:

```ruby run
require 'field_struct'

FieldStruct.types.lookup(:integer)                    # => FieldStruct::Types::Integer
FieldStruct::Types::Integer.option_schema.keys        # => [:in, :base, :strict]
FieldStruct::Types::Base.resolve_format('%Y')         # => "%Y"
```

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
