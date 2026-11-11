---
title: "How to validate nested structs and arrays"
description: "Declare nested shapes, find the element that is wrong, and re-assign after changing a child in place."
sidebar:
  label: "Nested structs and arrays"
  order: 6
---

A `Planting` holds several seedlings, one has a leaf count that is out of range, and you need to say which.

## 1. Declare the shape

A struct class works as a type, so a field can hold one, and `:array` with `of:` holds a list. Hashes passed in for them are built into structs.

```ruby run
class Seedling < FieldStruct::Base
  required :species, :string
  required :leaves, :integer, in: 1..99
end

class Planting < FieldStruct::Base
  required :label, :string
  required :seedlings, :array, of: Seedling
  optional :showpiece, Seedling
end

planting = Planting.new(label: 'P7', seedlings: [{ species: 'fern', leaves: 12 }, { species: 'moss', leaves: 0 }])
```

## 2. Read the parent's verdict

One invalid child makes the parent invalid. The parent says so once, on the field, and doesn't name the element.

```ruby run
planting.valid?                    # => false
planting.errors.to_h               # => {seedlings: ["is invalid"]}
planting.seedlings.first.valid?    # => true
```

## 3. Find the element

Every element is a struct with its own errors, so ask each one. If you want an indexed report, build it yourself.

```ruby run
bad = planting.seedlings.each_with_index.reject { |seedling, _| seedling.valid? }
bad.map(&:last)                    # => [1]

report = planting.seedlings.each_with_index.to_h { |s, i| [i, s.errors.to_h] }.reject { |_, errors| errors.empty? }
report                             # => {1 => {leaves: ["is invalid"]}}
```

The `"element at index 1 is invalid"` message belongs to plain elements checked through `element:` options, like strings with a `format:`. A struct element reports through itself instead.

## 4. Re-assign after changing a child in place

Validity gets computed when a value is assigned (see [Validity is computed on assignment](/explanation/validity-on-assignment/)). If you change a child later, the parent doesn't notice, whichever way the change goes.

```ruby run
planting.seedlings[1].leaves = 3
planting.valid?                    # => false, still stale

planting.seedlings = planting.seedlings
planting.valid?                    # => true
```

Assigning the field again runs coercion and validation again. `with` does too, and it hands back a new object:

```ruby run
Planting.new(label: 'P7', seedlings: [{ species: 'fern', leaves: 12 }]).with(label: 'P8').label   # => "P8"
```

:::caution
Pushing onto the array in place, `planting.seedlings << { species: 'x' }`, stores the raw element with no coercion. Build a fresh array and assign that.
:::

## See also

- [Types](/reference/field-struct/types/)
- [Validation and errors](/reference/field-struct/validation-and-errors/#validity-is-computed-on-assignment)
- [Validity is computed on assignment](/explanation/validity-on-assignment/)
