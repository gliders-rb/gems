---
title: "Instance API"
description: "What you can call on a FieldStruct instance: construction, readers and writers, copies, equality, inspect, pattern matching and the model_name helpers."
sidebar:
  order: 6
---

An instance of a `FieldStruct::Base` subclass is an ordinary Ruby object with a reader and a writer for each field. This page covers every call you can make on it, in the order they come up: build, read, change, copy, compare, print.

Rules: FS-B18 to FS-B31, FS-B111 to FS-B118. Validity and errors have their own page, [Validation and errors](/reference/field-struct/validation-and-errors/).

| Member | Returns |
|---|---|
| `.new(attrs = {})` | an instance, always, even when the input is invalid |
| `#assign_attributes(attrs)` | `self` |
| `#with(**changes)` | a new instance, the receiver is untouched |
| `#<name>`, `#<name>=` | the field's reader, and a coercing writer |
| `#attributes`, `#to_h` | a fresh Hash with Symbol keys, in declaration order |
| `#attribute_names` | the field names, also available on the class |
| `#errors`, `#valid?`, `#invalid?` | the `Errors` object, and validity |
| `#==`, `#eql?`, `#hash` | equality by class and attributes |
| `#dup`, `#clone` | a shallow copy that owns a copy of the errors |
| `#inspect` | `#<Name field: value, ...>` |
| `#deconstruct`, `#deconstruct_keys` | pattern matching |
| `#model_name`, `#to_model` | naming helpers |
| `#as_json`, `#to_json` | see [JSON and serialization](/reference/field-struct/json-and-serialization/) |

## new

```ruby
Klass.new(attrs = {})
```

`new` accepts a Hash or anything that responds to `to_hash`, and treats `nil` as an empty Hash. Symbol and String keys address the same field, and when both `'a'` and `:a` appear, the later one in hash order wins. Any other input raises `ArgumentError`. The message names the class and the input's class, never the value:

```
Seedling.new expects a Hash (or an object responding to #to_hash), got Array
```

Construction goes through these steps:

1. An empty `Errors` is created.
2. Under `unknown_attributes :raise`, unknown keys are checked first, before any default runs.
3. The defaults pass runs each field's setter with its default, in declaration order. A field with a `nil` default whose key is in the input is set straight to `nil`.
4. `assign_attributes(input)` calls the setter of each known key, in input order.
5. Cross-field validators run, when the class has any.
6. The instance is marked initialized, and that is what switches `immutable!` on.
7. The instance is frozen when the class uses `frozen!`.

A field left out is `nil` or its default, and a required field left out gets `"is required"`. A callable default runs once for each instance. Errors raised while building a nested struct travel up unchanged.

```ruby run
class Seedling < FieldStruct::Base
  required :species, :string
  optional :count, :integer, default: 1
end

Seedling.new(species: 'Fern').attributes        # => {species: "Fern", count: 1}
Seedling.new('species' => 'Fern', 'count' => '3').count   # => 3
Seedling.new(nil).species                      # => nil
Seedling.new(nil).valid?                   # => false

mapish = Object.new
def mapish.to_hash = {species: 'Moss'}
Seedling.new(mapish).species                  # => "Moss"

begin
  Seedling.new([])
rescue ArgumentError => e
  e.message   # => "Seedling.new expects a Hash (or an object responding to #to_hash), got Array"
end
```

## Readers, writers and attributes

Every field gets a reader with its name and a writer `name=`. The writer is permissive: `seedling.count = '30'` stores `30`, and a value it cannot read follows the [coercion policy](/reference/field-struct/validation-and-errors/).

`attributes` and `to_h` are one and the same: a fresh Hash with Symbol keys in declaration order. The keys are always the Ruby field names, even when `serialize` maps them elsewhere. `attribute_names` gives a new Array of names, on the class and on an instance, and unknown input keys never add to it.

## assign_attributes

```ruby
instance.assign_attributes(hash)   # => instance
```

Each known key goes through the full setter pipeline, so coercion, the field's policy and error rewriting all apply. The method returns `self` and leaves fields you did not mention alone. It does not rerun defaults or cross-field validators, and on an `immutable!` instance it raises `ImmutableError`. Unknown keys follow `unknown_attributes`. Unlike `new`, `assign_attributes(nil)` raises: `ArgumentError: Seedling#assign_attributes expects a Hash (or an object responding to #to_hash), got NilClass`.

## with

```ruby
instance.with(**changes)   # => a new instance
```

The result is a new instance of the receiver's own class (subclasses are safe), with the changes applied through the full setter pipeline. It works on an `immutable!` instance as well, and the copy is immutable too. Fields you leave unchanged carry their errors over the way `dup` does. Cross-field validators run again, callable defaults do not, and the copy is frozen if the receiver was. Called with no changes it returns an equal copy, never `self`.

A positional argument raises: `with({count: 1})` fails with `Seedling#with takes keyword arguments only, got 1 positional; pass a Hash as with(**hash)`, while `with(**hash)` works, and so do String keys. Under `:raise` a bad value raises and no copy comes back.

```ruby run
sprout = Seedling.new(species: 'Fern', count: 2)
copy = sprout.with(count: '5')
copy.count                         # => 5
sprout.count                         # => 2
sprout.with.equal?(sprout)           # => false
sprout.with == sprout                # => true
sprout.with('count' => 7).count        # => 7

begin
  sprout.with({count: 1})
rescue ArgumentError => e
  e.message   # => "Seedling#with takes keyword arguments only, got 1 positional; pass a Hash as with(**hash)"
end
```

## Equality and hashing

`==` and `eql?` hold when the other object is an instance of exactly the same class with equal attributes. A subclass instance never equals its parent's, in either direction, and errors and validity are ignored. `hash` is built from the class and the attributes, so equal instances collapse in a `Set` and work as Hash keys.

```ruby run
class Potted < Seedling; end

Seedling.new(species: 'Fern', count: 2) == Seedling.new(species: 'Fern', count: '2')   # => true
Seedling.new(species: 'Fern') == Potted.new(species: 'Fern')                      # => false
Potted.new(species: 'Fern') == Seedling.new(species: 'Fern')                      # => false
{Seedling.new(species: 'Fern') => :found}[Seedling.new(species: 'Fern')]           # => :found
```

## dup and clone

Both produce a shallow copy, so nested structs and arrays are shared with the original. The copy owns an `Errors` object seeded with copies of the original's messages, which means editing a field on the copy never alters the original's `valid?`. `dup` of a frozen instance comes back unfrozen, `clone` keeps it frozen, and `clone(freeze: false)` drops the freeze. Class-level immutability carries over.

```ruby run
original = Seedling.new(species: 'Fern', count: 2)
copy = original.dup
copy.count = 'lots'
original.valid?             # => true
copy.valid?                 # => false

frozen = Seedling.new(species: 'Fern').freeze
frozen.dup.frozen?                    # => false
frozen.clone.frozen?                  # => true
frozen.clone(freeze: false).frozen?   # => false
```

## inspect and pp

`inspect` prints `#<ClassName field: value, field: value>` in declaration order, each value through its own `inspect`. An anonymous class shows as `AnonymousFieldStruct`, and a class without fields prints `#<Name >`. An instance with errors gets ` errors: {field: ["message"]}` before the closing bracket, and a valid one gets no suffix. Sensitive non-nil values print as `[FILTERED]` while `nil` still shows. `pp` applies the same masking, nested structs and arrays of them included. `inspect` reads the errors as they are and never validates again.

```ruby run
Seedling.new(species: 'Fern', count: 2).inspect   # => '#<Seedling species: "Fern", count: 2>'
Seedling.new.inspect                       # => '#<Seedling species: nil, count: 1 errors: {species: ["is required"]}>'
Class.new(FieldStruct::Base).new.inspect   # => '#<AnonymousFieldStruct >'
```

## Pattern matching

`deconstruct_keys(keys)` gives every attribute for `nil` and `attributes.slice(*keys)` otherwise, so undeclared keys are simply absent. `deconstruct` gives the values in declaration order. Nested structs recurse since they speak the same protocol, and find patterns over arrays of structs work. Names mapped by `serialize`, descriptions and errors take no part.

```ruby run
sprout = Seedling.new(species: 'Fern', count: 2)
sprout.deconstruct_keys(nil)             # => {species: "Fern", count: 2}
sprout.deconstruct_keys([:species, :colour])   # => {species: "Fern"}
sprout.deconstruct                       # => ["Fern", 2]

result = case sprout
         in {species: String => name, count: Integer => n} then [name, n]
         end
result   # => ["Fern", 2]
```

## model_name and to_model

`Klass.model_name`, which instances also answer, returns a `FieldStruct::ModelName`, memoized per class. Form builders and other code that expects an ActiveModel-shaped object can read a name from it. `to_model` returns `self`.

| Reader | Value for `Seedling` |
|---|---|
| `name` | `"Seedling"`, the full class name |
| `element`, `singular` | `"seedling"`, the snake_case of the last `::` segment |
| `plural` | `"seedlings"`, only `element` plus `s` |
| `to_s`, `to_str` | the same as `name` |

The plural is naive by design: `Cactus` becomes `"cactuss"` and `Tomato` becomes `"tomatos"`. FieldStruct does not inflect.

```ruby run
Seedling.model_name.name       # => "Seedling"
Seedling.model_name.singular   # => "seedling"
Seedling.model_name.plural     # => "seedlings"
Seedling.new(species: 'Fern').model_name.element   # => "seedling"
Seedling.new(species: 'Fern').to_model.class       # => Seedling
```

## See also

- [Validation and errors](/reference/field-struct/validation-and-errors/)
- [Class macros](/reference/field-struct/class-macros/)
- [JSON and serialization](/reference/field-struct/json-and-serialization/)
- [Introspection and tooling](/reference/field-struct/introspection-and-tooling/)
