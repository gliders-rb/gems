---
title: "Class macros"
description: "Class-wide settings for a FieldStruct class (coercion_policy, unknown_attributes, immutable!, frozen!, validate, serialize) and how subclasses inherit each one."
sidebar:
  order: 5
---

A class macro sets behaviour for every instance of a class. Write it in the class body beside the field declarations. All of them are inherited, and when a subclass sets its own value the parent stays as it was (FS-I4).

Rules: FS-B25, FS-B26, FS-B29, FS-B30, FS-B43 to FS-B51, FS-B101 to FS-B103, FS-I4.

| Macro | Values | Default | Read with |
|---|---|---|---|
| `coercion_policy` | `:keep_raw`, `:replace`, `:raise` | `:keep_raw` | `coercion_policy` |
| `unknown_attributes` | `:ignore`, `:raise` | `:ignore` | `unknown_attributes` |
| `immutable!` | none | mutable | `immutable?` |
| `frozen!` | none | not frozen | `frozen_on_construct?` |
| `validate` | method names or a block | none | |
| `serialize` | a format and a mapping | none | `metadata.serialization(format)` |

Call `coercion_policy` or `unknown_attributes` with an argument to set it, and without one to read it. `immutable!` and `frozen!` take no arguments and cannot be undone. On `Base` itself both predicates are false.

## coercion_policy

```ruby
coercion_policy :keep_raw   # or :replace, :raise
```

This decides what happens when a type cannot read a value. The options are to keep the raw input and record a message, to store `nil` and record a message, or to raise `CoercionError`. A field can override the class setting through its own `coercion_policy:` option, and each policy is described on [Validation and errors](/reference/field-struct/validation-and-errors/). An unknown value raises at the macro call:

```
unknown coercion policy :bad (expected one of [:keep_raw, :replace, :raise])
```

```ruby run
class Forecast < FieldStruct::Base
  coercion_policy :replace
  optional :frost_c, :float
end

class StrictForecast < Forecast
  coercion_policy :raise
end

Forecast.new(frost_c: 'mild').frost_c     # => nil
Forecast.coercion_policy                  # => :replace
StrictForecast.coercion_policy            # => :raise
Forecast.coercion_policy                  # => :replace
FieldStruct::Base.coercion_policy         # => :keep_raw

begin
  StrictForecast.new(frost_c: 'mild')
rescue FieldStruct::CoercionError => e
  e.field_name   # => :frost_c
end
```

## unknown_attributes

```ruby
unknown_attributes :ignore   # or :raise
```

`:ignore` makes `new`, `assign_attributes` and `with` drop keys that match no field without comment. `:raise` raises `UnknownAttributeError` on any unknown key before a single value is assigned, and inside `new` that happens before the defaults pass, so no callable default runs. The message names every unknown key, and `keys` holds Symbols in input order. A String key is known whenever its Symbol is a field.

Only subclasses inherit the policy. A nested struct keeps its own, so a struct that contains it does not hand its setting down. An unknown value raises `unknown unknown_attributes policy :bad (expected one of [:ignore, :raise])`.

```ruby run
class Cutting < FieldStruct::Base
  unknown_attributes :raise
  required :species, :string
end

Cutting.new('species' => 'Moss').species   # => "Moss"

begin
  Cutting.new(species: 'Moss', rooted: true, tray: 'x')
rescue FieldStruct::UnknownAttributeError => e
  e.keys      # => [:rooted, :tray]
  e.message   # => "unknown attribute(s) for Cutting: :rooted, :tray"
end

class LooseCutting < FieldStruct::Base
  required :species, :string
end

LooseCutting.new(species: 'Moss', rooted: true).attributes   # => {species: "Moss"}
```

## immutable!

```ruby
immutable!
```

Setters work while `new` runs. After it returns, every setter and `assign_attributes` raises `ImmutableError` before coercing anything. Reading, `with`, `dup`, `as_json` and the rest carry on, and the copy `with` returns is immutable too. A subclass of a mutable parent may call it, and the parent stays mutable.

## frozen!

```ruby
frozen!
```

The instance gets frozen as `new` finishes, so setters raise Ruby's `FrozenError`. Readers, `attributes`, `as_json`, `to_json`, `valid?` (cross-field validators too) and changes to `errors` all still work, since the `Errors` object is not frozen. `frozen!` stands apart from `immutable!`. When a class uses both, the immutability check goes first and the error is `ImmutableError`.

|  | `immutable!` | `frozen!` |
|---|---|---|
| Setter after `new` | `ImmutableError` | `FrozenError` |
| Object frozen | no | yes |
| `with` copy | immutable | frozen |

```ruby run
class Glasshouse < FieldStruct::Base
  immutable!
  required :vents, :integer
end

class Labelled < FieldStruct::Base
  frozen!
  required :vents, :integer
end

Glasshouse.immutable?                  # => true
Glasshouse.new(vents: 4).frozen?       # => false
Labelled.frozen_on_construct?          # => true
Labelled.new(vents: 4).frozen?         # => true
Glasshouse.new(vents: 4).with(vents: 6).vents   # => 6

begin
  Glasshouse.new(vents: 4).vents = 6
rescue FieldStruct::ImmutableError => e
  e.message   # => "Glasshouse is immutable; cannot reassign vents"
end

begin
  Labelled.new(vents: 4).vents = 6
rescue FrozenError
  :frozen   # => :frozen
end
```

## validate

```ruby
validate :method_name, :other_method
validate { |record| ... }
```

This registers cross-field validators. When they run, what they may write to and how they are inherited is covered on [Validation and errors](/reference/field-struct/validation-and-errors/#cross-field-validation). A subclass copies the parent's list when it is created and appends its own. `validators` returns that list, and it is semi-internal, so its shape is not a promise.

## serialize

```ruby
serialize :json, internal_name: 'externalName'
```

This maps field names to outside names for one format. The keys are Ruby field names and must be declared already, so put `serialize` after the fields. Values are converted to Strings. An undeclared key raises:

```
serialize :json references undeclared field(s): :nope. Declare fields before calling serialize.
```

A class can hold several formats, though the gem itself uses only `:json`. Other format names are stored so downstream gems can read them. Declaring a format again replaces its whole mapping, and fields left out keep their own names. Mappings are inherited the way fields are: a subclass receives its parent's mapping when created and may replace one or add more. `metadata.serialization(:json)` returns the frozen mapping, or an empty frozen Hash for a format never declared. How the mapping applies when reading and writing JSON is on [JSON and serialization](/reference/field-struct/json-and-serialization/).

```ruby run
class Herbarium < FieldStruct::Base
  required :common_name, :string
  optional :pressed_on, :date
  serialize :json, common_name: :commonName, pressed_on: 'pressedOn'
end

Herbarium.metadata.serialization(:json)   # => {common_name: "commonName", pressed_on: "pressedOn"}
Herbarium.metadata.serialization(:csv)    # => {}
Herbarium.new(common_name: 'Sorrel').as_json.keys   # => [:commonName, :pressedOn]

begin
  Class.new(FieldStruct::Base) { serialize :json, nope: 'x' }
rescue ArgumentError => e
  e.message   # => "serialize :json references undeclared field(s): :nope. Declare fields before calling serialize."
end
```

## Inheritance in one place

- A subclass starts with a copy of the parent's fields and mappings as they stood when the subclass was created. Later additions to the parent do not reach subclasses that already exist.
- Policies, `immutable!`, `frozen!`, validators and `serialize` mappings all pass down. A subclass can change its own policies and the parent is not affected.
- A subclass cannot take anything away: `immutable!` has no undo, and an inherited validator cannot be dropped.

## See also

- [Validation and errors](/reference/field-struct/validation-and-errors/)
- [JSON and serialization](/reference/field-struct/json-and-serialization/)
- [Fields and options](/reference/field-struct/fields-and-options/)
- [Exceptions](/reference/field-struct/exceptions/)
