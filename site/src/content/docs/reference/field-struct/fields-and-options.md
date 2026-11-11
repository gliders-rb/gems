---
title: "Fields and options"
description: "Declaring fields with field, required and optional, the options that work on every type, and what happens to an option a type does not recognise."
sidebar:
  order: 1
---

A field is a name, a type and some options. Declare it in the class body with `required`, `optional` or `field`, and the gem adds a reader and a writer. Declarations are checked as the class body runs, so a mistake raises when the class loads, not the first time somebody uses it.

Rules: FS-B1 to FS-B17, FS-I14, FS-I17, FS-I19. Types live on [Types](/reference/field-struct/types/). Every error message a declaration can raise is gathered at the bottom of this page.

## required, optional and field

```ruby
required :name, :type, **options
optional :name, :type, **options
field    :name, :type, **options
```

`name` may be a Symbol or a String and ends up a Symbol. `type` is a registered name like `:string`, a `FieldStruct::Base` subclass (a nested struct), or a type class. The macros return the class's `Metadata`, not the field they just made, so fetch the field with `metadata[name]`.

| Macro | Required? |
|---|---|
| `required` | always, overriding any `required:` option you pass |
| `optional` | never, overriding any `required:` option you pass |
| `field` | only when you pass `required: true` |

```ruby run
class Plant < FieldStruct::Base
  required :species, :string
  optional :leaves, :integer
  field    :accession, :string, required: true
  field    :cultivar, :string
end

Plant.metadata[:species].required?     # => true
Plant.metadata[:leaves].required?      # => false
Plant.metadata[:accession].required?   # => true
Plant.metadata[:cultivar].required?    # => false
Plant.attribute_names                  # => [:species, :leaves, :accession, :cultivar]
```

Declare a name a second time and the new declaration replaces the old one, staying in the old position in `attribute_names`. A subclass begins with a snapshot of its parent's fields from the moment it was created. Fields added to the parent afterwards never reach existing subclasses, and a subclass may redeclare a field with a different type while the parent stays untouched.

```ruby run
class Seedling < FieldStruct::Base
  required :species, :string
  optional :height, :integer
end

class Specimen < Seedling
  optional :height, :float
  optional :label_url, :url
end

Seedling.attribute_names            # => [:species, :height]
Specimen.attribute_names            # => [:species, :height, :label_url]
Specimen.new(height: '2').height    # => 2.0
Seedling.new(height: '2').height    # => 2
```

## Universal options

Every type accepts these. They live on the field itself and are never passed to the type's `coerce`.

| Option | Values | Notes |
|---|---|---|
| `required:` | `true` or `false` | `required` and `optional` force it |
| `default:` | a literal, or anything that responds to `call` | `nil` means no default. A callable runs once for each instance, at construction, and its result passes through the setter like any other value |
| `coercion_policy:` | `:keep_raw`, `:replace`, `:raise` | overrides the class policy for this field. See [Validation and errors](/reference/field-struct/validation-and-errors/) |
| `description:` or `desc:` | String | aliases of each other. Passing both raises |
| `rbs_type:` | non-blank String | replaces the RBS type derived for the field |
| `sensitive:` | `true` or `false` only | masks a non-nil value as `[FILTERED]` in `inspect` and `pp` |

```ruby run
class Observation < FieldStruct::Base
  required :station, :string, desc: 'Weather station label'
  optional :scale, :symbol, enum: %i[metric imperial], default: :metric
  optional :logged_at, :time, default: -> { Time.at(0).utc }
  optional :remark, :string, default: 'calm', sensitive: true
end

obs = Observation.new(station: 'glasshouse')
obs.scale                                    # => :metric
obs.logged_at.to_i                           # => 0
obs.remark                                   # => "calm"
Observation.metadata[:station].description   # => "Weather station label"
Observation.metadata[:remark].sensitive?     # => true
```

A default applies only when the key is missing from the input. Pass an explicit `nil` over a non-nil default and `nil` is stored, so a required field then records `"is required"`. A default does satisfy `required`, because the check looks at the stored value. `with` never runs defaults again, and a literal Hash default on a nested field is coerced into the struct like any other input.

```ruby run
class Planting < FieldStruct::Base
  required :stage, :symbol, default: :sown
end

Planting.new.valid?                       # => true
Planting.new(stage: nil).valid?           # => false
Planting.new(stage: nil).errors[:stage]   # => ["is required"]
```

`Field#default` gives back the declared default as written and never calls a callable. Since `nil` means "no default", a default of `false`, `0`, `''` or `[]` still counts as one, and `default: nil` equals leaving the option out.

## Options that belong to a type

Each type declares the options it understands, like `format:` and `enum:` on strings or `round:` on floats. The full matrix is on [Types](/reference/field-struct/types/). The checks below run as the class body executes:

- the value has to be the shape the type expects, and `nil` is always allowed
- an option declared by some other registered type raises, and the message names the types it applies to
- an option the type itself requires (`of:` on `:array` and `:union`) has to be there

```ruby run
begin
  Class.new(FieldStruct::Base) { optional :petals, :integer, round: 2 }
rescue ArgumentError => e
  e.message   # => "round: option does not apply to Integer fields. It applies to: Float, BigDecimal."
end

begin
  Class.new(FieldStruct::Base) { optional :rainfall, :float, round: '2' }
rescue ArgumentError => e
  e.message   # => 'round: on Float expects Integer, got String ("2")'
end
```

The "applies to" list is built from the class's registry chain. A custom type that declares a new option therefore reserves that key against every other type in the chain.

## Pass-through options

Any key that is neither universal nor declared by a registered type is a pass-through option. It sits in `Field#options` exactly as written and does nothing at runtime. Exporters such as the adapter gems read these keys, which lets `avro_doc:` or `json_schema:` sit right beside the field it describes.

```ruby run
class Hedge < FieldStruct::Base
  optional :metres, :integer, avro_doc: 'length in metres', json_schema: {minimum: 1}
end

Hedge.metadata[:metres].options[:avro_doc]       # => "length in metres"
Hedge.metadata[:metres].options[:json_schema]    # => {minimum: 1}
Hedge.new(metres: '12').metres                   # => 12
```

Pass-through keys belong to the field level only. Inside an array's `element:` they raise, the same as any key the element type does not know.

The `options` Hash is frozen and holds native and pass-through options only, with presets already turned into concrete values: `values: :numeric` on a boolean is stored as its Hash, `format: :v4` on a UUID as its Regexp. Two entries stay as declared, a temporal `format:` (so tooling can read the preset name) and `zone:`. On an array field `of:` is swapped for `of_type:`, placed first. A string-shaped type without `format:` gets its default format added at the end (`:uuid`, `:url`, `:email`), and a temporal type stores `format: nil` if you declare none. That prefilled `format:` is the one option the gem supplies for you.

## Reserved names

A field may not use a name that `FieldStruct::Base` depends on. The check covers Symbols and Strings and all three macros.

```
errors attributes attribute_names assign_attributes as_json to_json to_h
to_model model_name inspect hash class send public_send freeze
instance_variable_set initialize initialize_copy raise with dup
deconstruct deconstruct_keys
```

The gem's private helpers are reserved as well, while `method`, `name`, `type` and `format` are fine. The complete list is `FieldStruct::Base::RESERVED_FIELD_NAMES`.

```ruby run
begin
  Class.new(FieldStruct::Base) { required :errors, :string }
rescue ArgumentError => e
  e.message.start_with?('field :errors is reserved')   # => true
end

class Nursery < FieldStruct::Base
  required :name, :string
  required :type, :string
  serialize :json, type: 'kind'
end

Nursery.new(name: 'Heath', type: 'alpine').as_json   # => {name: "Heath", kind: "alpine"}
```

If the outside key is a reserved name, call the field something else and map it with `serialize :json`. See [JSON and serialization](/reference/field-struct/json-and-serialization/).

## Resolving the type argument

The `type` argument can be:

- a registered name, as a Symbol or String, resolved through the class's [registry chain](/reference/field-struct/registries-and-custom-types/)
- a `FieldStruct::Base` subclass, which makes a nested field
- a registered name whose value is a `Base` subclass, which also makes a nested field
- a type class that is not a `Base` subclass, used as is with no registration

`:decimal` and `:big_decimal` resolve to one class. An unknown name raises `KeyError` at declaration, and so does an unknown name in `of:` or among union members.

```ruby run
begin
  Class.new(FieldStruct::Base) { required :species, :strng }
rescue KeyError => e
  e.message   # => "no FieldStruct type registered for :strng"
end

FieldStruct.types.lookup(:decimal).equal?(FieldStruct.types.lookup(:big_decimal))   # => true
```

## Field objects

`metadata[name]` returns a `FieldStruct::Field`. Fields are frozen after construction, so sharing and caching them is safe. The public readers:

| Reader | Returns |
|---|---|
| `name` | Symbol |
| `type` | the resolved type class (`:decimal` gives `Types::BigDecimal`, a struct gives `Types::Nested`) |
| `type_instance` | the instance used when assigning, one per field |
| `required?`, `sensitive?` | Boolean |
| `default` | the declared default, never evaluated |
| `options` | the frozen options Hash |
| `coercion_policy`, `rbs_type` | `nil` when unset |
| `description`, `desc` | the same String, or `nil` |

```ruby run
field = Plant.metadata[:leaves]
field.name                  # => :leaves
field.type                  # => FieldStruct::Types::Integer
field.frozen?               # => true
field.options               # => {}
```

A description shows up in `Metadata#to_h`, `describe` and `Field#inspect`, and nowhere in `attributes`, `as_json`, `to_json` or pattern matching. A subclass that redeclares the field replaces it, even with `nil`. See [Introspection and tooling](/reference/field-struct/introspection-and-tooling/) for the rest.

## Declaration errors

All of these raise while the class body runs, as `ArgumentError` unless marked otherwise. The checks go in this order and the first failure wins: reserved name, universal options, unknown or wrong-type keys, required native options, option shapes, then the type's own value checks.

| Situation | Message |
|---|---|
| unknown type name | `KeyError`: `no FieldStruct type registered for :tuber` |
| reserved name | `field :errors is reserved: ...` |
| `description:` and `desc:` both given | `pass either description: or desc:, not both` |
| bad field `coercion_policy:` | `unknown coercion policy :bad (expected one of [:keep_raw, :replace, :raise])` |
| `rbs_type:` blank or not a String | `rbs_type: must be a non-empty String of RBS ...` |
| `sensitive:` not true or false | `sensitive: must be true or false, got Integer` |
| option on the wrong type | `round: option does not apply to Integer fields. It applies to: Float, BigDecimal.` |
| option of the wrong shape | `round: on Float expects Integer, got String ("2")` |
| `:array` without `of:` | ``array field requires an `of:` option naming the element type`` |
| `:union` without `of:` | ``union field requires an `of: [...]` option naming the member types`` |

The messages for presets, zones and `element:` are on [Types](/reference/field-struct/types/) and [Dates, times and zones](/reference/field-struct/dates-and-times/).

## See also

- [Types](/reference/field-struct/types/)
- [Class macros](/reference/field-struct/class-macros/)
- [Validation and errors](/reference/field-struct/validation-and-errors/)
- [Introspection and tooling](/reference/field-struct/introspection-and-tooling/)
