---
title: "Registries and custom types"
description: "How type names are resolved through registries and namespaces, the Registry API, how to write and register your own type, and use_alias!."
sidebar:
  order: 8
---

Every type name, `:string` for one, is resolved through a registry. FieldStruct ships a single registry holding the built-in types, and a module can attach its own registry to give the structs inside it more names. This page walks through name resolution, the `Registry` API, how to write a type, and the global `use_alias!`.

Rules: FS-B2, FS-B5, FS-B6, FS-B118, FS-B123 to FS-B126.

## How a name is resolved

Every declaration looks for a registry in this order:

1. Take the class's `name` and cut off its last `::` segment.
2. Try what is left as a constant, then shorter and shorter prefixes. The first constant that responds to `field_types` provides the registry.
3. If nothing responds, fall back to `FieldStruct.types`.

The class's own constant is never consulted, and an anonymous class always gets `FieldStruct.types`. For `Arboretum::Collection::Specimen` the lookup tries `Arboretum::Collection`, then `Arboretum`, then falls back. Nothing is cached, so resolution reruns at every declaration. An unknown name raises `KeyError` at declaration, including a name given to `of:` and the members of a union.

`FieldStruct.new_registry` gives the new registry `FieldStruct.types` as its parent unless told otherwise, so a namespace adds names and still has the built-ins.

## FieldStruct.types and new_registry

`FieldStruct.types` is the memoized base registry. It has no parent and holds exactly these names:

| Name | Type |
|---|---|
| `:string`, `:immutable_string`, `:binary` | strings |
| `:uuid`, `:url`, `:email` | string-shaped |
| `:symbol` | `Symbol` |
| `:integer`, `:float` | numbers |
| `:big_decimal`, `:decimal` | the same class |
| `:boolean` | `true` or `false` |
| `:date`, `:time`, `:datetime` | temporal |
| `:value`, `:array`, `:union` | any value, arrays, unions |

Struct classes have no registered name. Pass one to a field macro and it builds the nested type itself.

```ruby
FieldStruct.new_registry(parent = FieldStruct.types, &block)
```

`new_registry` returns a `Registry` with that parent. The block runs with the new registry as `self`, so `register` needs no receiver. Pass `nil` for a registry with no parent, which has to register every type its classes use, or a missing one raises `KeyError`. Skip the block and you still get the registry back.

## The Registry API

| Member | Behaviour |
|---|---|
| `Registry.new(parent = nil)` | an empty registry, with no parent unless given |
| `#parent` | the parent registry, or `nil` |
| `#register(name, target)` | stores a class under `name` (a String or Symbol) and returns the registry. Registering a name again overwrites it |
| `#lookup(name)` | the class, searching this registry first and then up the chain. An unknown name raises `KeyError` |
| `#key?(name)` | true if the chain knows the name |
| `#type_classes` | the distinct classes the registry can resolve |
| `#inspect` | `#<FieldStruct::Registry types=[:a, :b]>`, with ` parent` before the `>` when there is one |

A Symbol `target` makes the name an alias. The target is resolved immediately through the chain and the class it finds is what gets stored, so registering the target again later doesn't move the alias, and an unknown target raises `KeyError` at registration. An entry in a child shadows a parent entry with the same name.

```ruby run
class Accession < FieldStruct::Types::Base
  def coerce(value, **)
    value.nil? ? nil : value.to_s.delete('-')
  end

  def ruby_type = String
end

registry = FieldStruct::Registry.new
registry.key?(:accession)                     # => false
registry.register(:accession, Accession).register('tag_code', :accession)
registry.lookup('accession')                  # => Accession
registry.lookup(:tag_code).equal?(Accession)  # => true
registry.inspect                              # => "#<FieldStruct::Registry types=[:accession, :tag_code]>"

begin
  registry.lookup(:nope)
rescue KeyError => e
  e.message   # => "no FieldStruct type registered for :nope"
end

child = FieldStruct.new_registry { register :accession, Accession }
child.parent.equal?(FieldStruct.types)        # => true
child.key?(:string)                           # => true
FieldStruct.types.key?(:accession)            # => false
FieldStruct.types.lookup(:decimal).equal?(FieldStruct.types.lookup(:big_decimal))   # => true
```

## Namespace registries

A module that defines `self.field_types` and returns a registry hands it to every struct declared inside, at any depth. The nearest module wins.

```ruby run
module Arboretum
  def self.field_types
    @field_types ||= FieldStruct.new_registry do
      register :accession, Accession
      register :tag_code, :accession
    end
  end

  module Collection
    class Specimen < FieldStruct::Base
      required :species, :string
      required :accession, :accession
      optional :old_tag, :tag_code
    end
  end
end

Arboretum::Collection::Specimen.new(species: 'Ginkgo', accession: '1984-0231-07').accession   # => "1984023107"
Arboretum::Collection::Specimen.new(species: 'Ginkgo', accession: '5-6', old_tag: '7-8').old_tag   # => "78"
```

## Writing a type

Write a type as a subclass of `FieldStruct::Types::Base`. It can define these members:

| Member | Contract |
|---|---|
| `#coerce(value, **options)` | returns the coerced value, and `nil` for `nil`. Raise `ArgumentError`, `TypeError` or `RangeError` to refuse a value. List your options as keywords and finish with a `**` catch-all, since the setter hands over every field option, pass-through ones included |
| `#ruby_type` | a class, or an Array of classes |
| `#missing?(value)` | decides what `required` rejects. Defaults to `value.nil?` |
| `#rbs_type` | an RBS type String that replaces the generated one. Defaults to `nil` |
| `.own_option_schema` | the options your type owns, as `{name => option(type: [Class])}`. Defaults to `{}` |
| `.resolve_options(options)` | a declaration-time hook that validates values and expands presets into concrete ones |

The base class raises `NotImplementedError` when `coerce` or `ruby_type` is missing. Keep messages free of the input value and name the class, like the built-ins do (FS-I5). A type class that doesn't inherit from `Base` can go straight into a declaration with no registry at all.

Option keys are recognised by searching the whole registry chain, so a key your type declares becomes reserved for every other type in that chain, and using it on a type that doesn't declare it raises. A key declared only by an unregistered type is a plain pass-through option.

```ruby run
class Moisture < FieldStruct::Types::Base
  def self.own_option_schema
    {ceiling: option(type: [Integer])}
  end

  def coerce(value, ceiling: 100, **)
    return nil if value.nil?

    level = Float(value.to_s.delete_suffix('%'))
    raise ArgumentError, "Moisture fields expect 0 to #{ceiling}" unless (0..ceiling).cover?(level)

    level
  end

  def ruby_type = Float
  def rbs_type = '::Float'
end

module Greenhouse
  def self.field_types
    @field_types ||= FieldStruct.new_registry { register :moisture, Moisture }
  end

  class Reading < FieldStruct::Base
    required :soil, :moisture, ceiling: 60
    optional :air, :moisture
  end
end

Greenhouse::Reading.new(soil: '35%').soil          # => 35.0
Greenhouse::Reading.new(soil: '75%').valid?        # => false
Greenhouse::Reading.new(soil: '75%').errors[:soil].first   # => "could not be coerced: Moisture fields expect 0 to 60"
Greenhouse::Reading.new(soil: 10, air: '88').air   # => 88.0
Greenhouse::Reading.metadata[:soil].options        # => {ceiling: 60}
Greenhouse::Reading.metadata[:soil].type           # => Moisture
FieldStruct.types.key?(:moisture)                  # => false

class Probe < FieldStruct::Base
  optional :level, Moisture
end

Probe.new(level: '5').level                        # => 5.0
```

### Changing a built-in's defaults

Built-in types read a handful of class-level hooks. A subclass that overrides one changes the default for every field using that registered subclass, with no per-field option. `default_format` provides the pre-filled `format:` for `:uuid`, `:url` and `:email`. `default_round` sets the rounding of `:float` and `:decimal` and is `nil` by default. `default_truthy` and `default_falsy` hold the boolean vocabulary, and `presets` the named formats. Only `default_format` is written into a field's options. The other defaults apply inside `coerce` and never show up in `options`.

```ruby run
class WetDryBoolean < FieldStruct::Types::Boolean
  def self.default_truthy = %w[wet]
  def self.default_falsy = %w[dry]
end

module SoilSurvey
  def self.field_types
    @field_types ||= FieldStruct.new_registry { register :boolean, WetDryBoolean }
  end

  class Patch < FieldStruct::Base
    optional :soggy, :boolean
  end
end

SoilSurvey::Patch.new(soggy: 'wet').soggy          # => true
SoilSurvey::Patch.new(soggy: 'true').valid?        # => false
SoilSurvey::Patch.new(soggy: true).soggy           # => true
SoilSurvey::Patch.metadata[:soggy].options         # => {}
```

## use_alias!

```ruby
FieldStruct.use_alias!(name = :FS)
```

Defines a top-level constant pointing at `FieldStruct`, and makes every library `inspect` (`Metadata`, `Field`, `Errors`, `Registry` and the types) use that name as its prefix. Calling it again with the same constant is fine. If the constant is already defined as something else it raises `NameError`, with a message starting `::FS is already defined (`. `FieldStruct.inspect_namespace` returns the current prefix, `'FieldStruct'` by default.

The change is global and can't be undone, so call it once at boot, if at all. That is why this example comes last on the page.

```ruby run
FieldStruct.inspect_namespace      # => "FieldStruct"
FieldStruct.use_alias!
FS::Base.equal?(FieldStruct::Base) # => true
FieldStruct.inspect_namespace      # => "FS"
FieldStruct::Errors.new.inspect    # => "#<FS::Errors empty>"
FieldStruct.use_alias!(:FS).equal?(FieldStruct)   # => true
```

## See also

- [Fields and options](/reference/field-struct/fields-and-options/)
- [Types](/reference/field-struct/types/)
- [Introspection and tooling](/reference/field-struct/introspection-and-tooling/)
- [Exceptions](/reference/field-struct/exceptions/)
