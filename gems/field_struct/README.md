# field_struct

Typed plain Ruby objects. You declare a field's name, type and options. Every assignment coerces the value, records
what's wrong with it, and leaves the object usable. Nothing raises just because the input was bad.

```ruby
gem 'field_struct'
```

Ruby 3.3 or newer. Runtime dependencies: `oj`, `bigdecimal`, `tzinfo`. ActiveSupport and ActiveModel are never required.

## A first model

<!-- doctest -->
```ruby
require 'field_struct'

class Plant < FieldStruct::Base
  required :species, :string
  optional :leaves, :integer, in: 1..5000
  optional :tags,  :array, of: :string
end

plant = Plant.new(species: 'Monstera', leaves: '412', tags: %w[tropical shade])
plant.leaves          # => 412
plant.valid?         # => true
plant.to_h           # => {species: "Monstera", leaves: 412, tags: ["tropical", "shade"]}
```

Bad input doesn't raise. It's recorded, and the raw value stays where it was assigned:

<!-- doctest -->
```ruby
require 'field_struct'

class Plant < FieldStruct::Base
  required :species, :string
  optional :leaves, :integer, in: 1..5000
end

bad = Plant.new(species: '  ', leaves: 'many')
bad.valid?                  # => false
bad.leaves                   # => "many"
bad.errors.to_h[:species]     # => ["is required"]
bad.errors.full_messages.first   # => "Species is required"

Plant.new(species: 'Monstera', leaves: 9999).errors.to_h   # => {leaves: ["is invalid"]}
```

That's the whole model: assign anything, read back the coerced value, and ask `valid?` when you care.

## Declaring fields

`required`, `optional` and `field` take a name, a type and options.

| Macro | Meaning |
|---|---|
| `required :name, :type, **options` | the field must be present (`valid?` is false without it) |
| `optional :name, :type, **options` | the field may be missing |
| `field :name, :type, **options` | same as `optional`, unless you pass `required: true` |

A type is a registered name (`:string`), a `FieldStruct::Base` subclass (a nested struct), or a type class. Required means
"not missing": `nil` is missing, and so are blank strings and empty arrays. It doesn't mean "non-nil" at assignment time.

### Options for every type

| Option | Meaning |
|---|---|
| `default:` | a value, or a callable run per instance (`default: -> { Time.now }`) |
| `coercion_policy:` | what a failed coercion does: `:keep_raw` (default), `:replace`, `:raise` |
| `description:` / `desc:` | text shown by `describe` |
| `rbs_type:` | an RBS type string that replaces the derived one |
| `sensitive:` | `true` masks the value in `inspect` |

### Types

| Type | Ruby class | Native options |
|---|---|---|
| `:string`, `:immutable_string` | `String` | `format:`, `enum:`, `strict:` |
| `:uuid`, `:url`, `:email` | `String` | `format:` (presets), `enum:`, `strict:` |
| `:binary` | `String` (binary) | as `:string` |
| `:symbol` | `Symbol` | `enum:` |
| `:integer` | `Integer` | `in:`, `base:`, `strict:` |
| `:float` | `Float` | `round:`, `in:` |
| `:decimal` (`:big_decimal`) | `BigDecimal` | `round:`, `in:` |
| `:boolean` | `true` / `false` | `values:` |
| `:date` | `Date` | `format:`, `in:` |
| `:time`, `:datetime` | `Time`, `DateTime` | `format:`, `in:`, `zone:` |
| `:value` | anything | none |
| `:array` | `Array` | `of:` (required), `element:` |
| `:union` | one of several | `of:` (required) |
| a struct class | that struct | none |

[USAGE.md](USAGE.md) has every option with an example.

## Coercion

<!-- doctest -->
```ruby
require 'field_struct'

class Sample < FieldStruct::Base
  required :celsius,  :float, round: 1
  optional :unit,     :symbol, enum: %i[c f]
  optional :probe,    :uuid
  optional :taken_on, :date, format: :iso8601
  optional :flagged,  :boolean, values: :english
end

sample = Sample.new(celsius: '21.456', unit: 'c', taken_on: '2026-03-01', flagged: 'yes')
sample.celsius    # => 21.5
sample.unit       # => :c
sample.taken_on   # => Date.new(2026, 3, 1)
sample.flagged    # => true
```

Writers are permissive. `sample.celsius = 'warm'` doesn't raise: it keeps `'warm'`, adds
`could not be coerced: ...` to `errors`, and `valid?` turns false. Change that per class or per field with
`coercion_policy` (see below).

## Nested structs, arrays and unions

<!-- doctest -->
```ruby
require 'field_struct'

class Bed < FieldStruct::Base
  required :habitat, :string
end

class Greenhouse < FieldStruct::Base
  required :label, :string
  optional :main_bed, Bed
  optional :annexes, :array, of: Bed
  optional :steward, :union, of: %i[integer email]
end

house = Greenhouse.new(label: 'East', main_bed: {habitat: 'Fen'}, annexes: [{habitat: 'Heath'}], steward: '42')
house.main_bed.habitat        # => "Fen"
house.annexes.map(&:habitat)  # => ["Heath"]
house.steward                 # => 42
Greenhouse.new(label: 'East', main_bed: {habitat: ''}).valid?   # => false
```

A union tries its members in order and keeps the first that accepts the value.

## JSON

<!-- doctest -->
```ruby
require 'field_struct'

class Station < FieldStruct::Base
  required :contact, :email
  optional :installed, :datetime, format: :iso8601
  serialize :json, installed: 'installed_at'
end

station = Station.from_json('{"contact":"rain@example.org","installed_at":"2026-01-02T03:04:05Z"}')
station.contact                  # => "rain@example.org"
station.installed.year           # => 2026
station.as_json[:installed_at]   # => "2026-01-02T03:04:05Z"
station.to_json                  # => '{"contact":"rain@example.org","installed_at":"2026-01-02T03:04:05Z"}'
```

JSON goes through Oj. `from_json` raises `EncodingError` for malformed JSON and `ArgumentError` when the root isn't an
object. Error messages never echo the input.

## Policies

<!-- doctest -->
```ruby
require 'field_struct'

class Tally < FieldStruct::Base
  coercion_policy :raise        # a failed coercion raises FieldStruct::CoercionError
  unknown_attributes :raise     # an unexpected key raises FieldStruct::UnknownAttributeError
  immutable!                    # setters raise FieldStruct::ImmutableError after new
  required :stems, :integer
end

tally = Tally.new(stems: 3)
tally.with(stems: 4).stems   # => 4
tally.stems                  # => 3
```

`frozen!` freezes instances at the end of `new`. `with(**changes)` returns a copy and leaves the receiver alone.

## Cross-field rules

<!-- doctest -->
```ruby
require 'field_struct'

class Watering < FieldStruct::Base
  required :days, :integer
  optional :litres, :integer
  validate :litres_fit

  def litres_fit
    errors.add(:base, 'Forty litres at most') if litres && litres > 40
  end
end

Watering.new(days: 2, litres: 60).errors.to_h   # => {base: ["Forty litres at most"]}
```

Cross-field messages go under `:base`. Validators run at the end of `new` and `with`, and on every `valid?`.

## Looking at a model

`Plant.describe` prints one line per field with its type and options. `Plant.metadata.to_h` gives the same as data.
`inspect` shows the values (and the errors, if any); fields marked `sensitive: true` print as `[FILTERED]`.

## Types for your models

`FieldStruct::RBS.generate(Plant)` writes an RBS class for a model, so Steep or your editor know that `plant.leaves` is an
`Integer?`. The gem's own signatures ship in `sig/`.

<!-- doctest -->
```ruby
require 'field_struct'

class Plant < FieldStruct::Base
  required :species, :string
  optional :leaves, :integer
end

puts FieldStruct::RBS.generate(Plant).lines.drop(3)
```

## Turning JSON into a model

`FieldStruct::Scaffold.from_json` reads sample JSON and prints the model class that fits it. Run it once, then edit
the result.

## Your own types

Subclass `FieldStruct::Types::Base`, implement `coerce` and `ruby_type`, and register the class under a name in a
registry that lives on your module:

<!-- doctest -->
```ruby
require 'field_struct'

class Cents < FieldStruct::Types::Base
  def coerce(value, **)
    value.nil? ? nil : Integer(value)
  end

  def ruby_type
    Integer
  end
end

module Nursery
  def self.field_types
    @field_types ||= FieldStruct.new_registry { register :cents, Cents }
  end

  class Seedling < FieldStruct::Base
    required :yield_kg, :cents
  end
end

Nursery::Seedling.new(yield_kg: '250').yield_kg   # => 250
```

## More

- [USAGE.md](USAGE.md): the reference, example first.
- [docs/getting_started.md](docs/getting_started.md): which API for which task, what each error means, common mistakes, Rails.
- [CHANGELOG.md](CHANGELOG.md)
- [AGENTS.md](AGENTS.md): short guide for coding agents.

MIT licensed.
