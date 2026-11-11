---
title: "Validation and errors"
description: "The setter pipeline, every built-in error message, the three coercion failure policies, cross-field validators and the Errors API."
sidebar:
  order: 4
---

A field setter coerces the value, stores it, and validates that one field. Problems go onto `obj.errors` and aren't raised unless you ask for `:raise`. Building an object and asking whether it is valid are two different things: `new` always hands back an instance, and `valid?` reports the outcome.

Rules: FS-B24, FS-B32 to FS-B51, FS-I1 to FS-I3, FS-I5. The macros that set policies live on [Class macros](/reference/field-struct/class-macros/).

## The setter pipeline

`name=(value)` runs these steps in order, and `new`, `assign_attributes` and `with` run the same ones for every key.

1. If the instance is initialized and the class is `immutable!`, raise `ImmutableError`.
2. Coerce with the field's type. A failure (`ArgumentError`, `TypeError` or `RangeError`) is handed to the [coercion policy](#coercion-failure-policy) and the pipeline stops.
3. Store the coerced value.
4. Validate the field (below).

Any other exception, like `NoMethodError` or a `FieldStruct::Error`, propagates. The setter returns the coerced value. Assigning a field again reruns the whole pipeline and rewrites that field's errors while leaving the other fields' errors alone. Under `:keep_raw`, a later good value clears an earlier coercion error.

## Field validation

Once coercion succeeds, validation goes in this order and stops at the first step that applies:

1. Clear that field's errors.
2. If the type calls the value missing, add `"is required"` when the field is required and stop. A missing optional value is fine.
3. Otherwise, when the value fails `format:` (a Regexp only), `enum:` or `in:`, or is an invalid nested struct or holds one, add `"is invalid"`. It is added once, however many checks fail.
4. For an array with `element:` options, add the element-index message (see [Types](/reference/field-struct/types/)).

| Message | When |
|---|---|
| `"is required"` | a required field is missing: nil, a blank String, an empty Array |
| `"is invalid"` | `format:`, `enum:` or `in:` failed, or a nested struct inside is invalid |
| `"element at index 1 is invalid"` | an element of an array failed an `element:` check |
| `"could not be coerced: <reason>"` | the type couldn't read the value |
| anything you add | from `validate` or `errors.add` |

`format:`, `enum:` and `in:` can be combined, and any failure gives a single `"is invalid"`. `nil` never fails them. A Symbol or String `format:` (temporal presets and strftime strings) only drives parsing and adds no error. Coercion goes first, so `'10'` is already `10` when `in:` looks at it.

When coercion fails on a required field, only the coercion error is recorded, never `"is required"` as well, even if `:replace` stored `nil`. Defaults satisfy `required`, because the check looks at the stored value.

Messages carry the class of the input, never the value (FS-I5). That covers coercion errors, `CoercionError`, union and array messages, `from_json` errors and the `cause` chain, so it is safe to log them. Custom types write their own messages, and those should name the class as well.

```ruby run
class Seedling < FieldStruct::Base
  required :tag, :string, format: /\A[A-Z]{2}-\d+\z/
  optional :count, :integer, in: 1..40
  optional :stage, :symbol, enum: %i[sprout potted hardened]
end

seedling = Seedling.new(tag: 'zz', count: 'a dozen')
seedling.valid?                     # => false
seedling.errors[:tag]               # => ["is invalid"]
seedling.errors[:count].first.start_with?('could not be coerced')   # => true
seedling.errors.full_messages.first # => "Tag is invalid"
Seedling.new.errors[:tag]           # => ["is required"]
Seedling.new(tag: 'FE-7', count: 400).errors[:count]   # => ["is invalid"]
Seedling.new(tag: 'FE-7', count: nil, stage: nil).valid?   # => true
```

## Validity is computed on assignment

`valid?` runs the cross-field validators when the class has any, then reports `errors.empty?`. `invalid?` says the opposite. Per-field errors are set at assignment and never recomputed afterwards. Changing a nested struct, or an element of an array, in place doesn't refresh the parent in either direction, and pushing onto an array in place stores the raw element without coercion. To rerun coercion and validation, assign the field again or use `with` or `assign_attributes`.

An invalid nested struct gives the parent field `"is invalid"` when it is assigned. So does an Array containing at least one invalid struct, and so does a bare struct assigned to a `:value` field. Only the value itself and the elements of an Array are inspected, so a struct inside a Hash value goes unchecked.

```ruby run
class Tray < FieldStruct::Base
  required :cells, :integer
end

class Nursery < FieldStruct::Base
  optional :tray, Tray
end

nursery = Nursery.new(tray: {cells: 24})
nursery.valid?                   # => true
nursery.tray.cells = 'plenty'
nursery.valid?                   # => true
nursery.tray = nursery.tray
nursery.errors[:tray]            # => ["is invalid"]

seedling = Seedling.new(tag: 'zz')
seedling.tag = 'FE-7'
seedling.valid?                  # => true
```

## Coercion failure policy

When a type refuses a value, the policy in force is the field's `coercion_policy:` if it has one, otherwise the class's, which defaults to `:keep_raw`.

| Policy | What happens |
|---|---|
| `:keep_raw` | the raw input is stored and a single `"could not be coerced: ..."` message is recorded |
| `:replace` | the field becomes `nil` and the same message is recorded |
| `:raise` | the setter raises `FieldStruct::CoercionError` and the old value stays |

`:keep_raw` and `:replace` skip the validation steps, so the coercion message never comes with `"is required"` or `"is invalid"`. An invalid object under `:keep_raw` can thus hold a value of the wrong class, so check `valid?` before trusting a value.

For arrays, a single refused element fails the whole array under the policy. The message lists zero-based indexes, never values: `element at index 1: <reason>`, or `elements at index 1, 4 (index 1 shown): <reason>`, with at most five indexes before `and N more`.

`CoercionError` has `field_name` (a Symbol) and `original`, the coercion exception, which is also its `cause`. The message reads `could not coerce Integer input for fruit: <reason>`. A field-level `coercion_policy:` is inherited along with the field, and a subclass that redeclares the field without it loses the override.

```ruby run
class Trial < FieldStruct::Base
  optional :sprouts, :integer
  optional :buds, :integer, coercion_policy: :replace
  optional :fruit, :integer, coercion_policy: :raise
  required :stems, :integer, coercion_policy: :replace
end

trial = Trial.new(sprouts: 'few', buds: 'many', stems: 'tall')
trial.sprouts                  # => "few"
trial.buds                     # => nil
trial.errors[:stems].size      # => 1
trial.errors[:stems].first.start_with?('could not be coerced:')   # => true

begin
  Trial.new(fruit: 'ripe')
rescue FieldStruct::CoercionError => e
  e.field_name            # => :fruit
  e.original.class        # => ArgumentError
  e.message.start_with?('could not coerce String input for fruit:')   # => true
end
```

## Cross-field validation

`validate` takes method names, which are called on the record with no arguments, or a block, which is called with the record. Every name and every block is a validator of its own. You can mix the two forms and stack calls, and validators run in declaration order. `validate` returns the class.

Validators run after the per-field checks: once at the end of `new` and `with` (only when the class declares any), and again on every `valid?`. `errors[:base]` is cleared before each run, so cross-field messages belong under `:base`. Per-field errors are left alone, which means a validator writing to a named field must clean that entry up itself. A subclass gets a copy of its parent's validators and adds its own. An inherited one can't be removed.

Validators have to cope with nil fields, since the record may be invalid. The library doesn't guard against an exception raised inside a validator. `assign_attributes` doesn't rerun validators, but `valid?` does.

```ruby run
class Band < FieldStruct::Base
  required :coldest, :integer
  required :warmest, :integer
  validate :ordered
  validate { |band| band.errors.add(:base, 'no variation') if band.coldest == 0 && band.warmest == 0 }

  def ordered
    errors.add(:base, 'warmest must exceed coldest') if coldest && warmest && warmest <= coldest
  end
end

Band.new(coldest: 9, warmest: 4).errors[:base]    # => ["warmest must exceed coldest"]
Band.new(coldest: 0, warmest: 0).errors[:base]    # => ["warmest must exceed coldest", "no variation"]
Band.new(coldest: -2, warmest: 11).valid?         # => true

band = Band.new(coldest: -2, warmest: 11)
band.warmest = -5
band.errors[:base]                                # => []
band.valid?                                       # => false
band.errors[:base]                                # => ["warmest must exceed coldest"]
```

## The Errors API

`obj.errors` is a `FieldStruct::Errors`, a plain value object that doesn't depend on ActiveModel. Keys are Symbols, though a String key works anywhere you read one.

| Member | Returns |
|---|---|
| `#[](field)` | the field's messages, or a throwaway `[]` that is not stored |
| `#add(field, message)` | appends a message, creating the entry if needed |
| `#clear(field)` | removes the field's entry and returns `nil` |
| `#empty?` | true when no field has a message |
| `#to_h`, `#messages` | `{field => [messages]}` for fields that have messages, a new Hash on each call, ordered by when each field first got a message |
| `#full_messages` | `"Name is required"`: the humanized field name, a space, the message. `:base` gets no prefix |
| `#inspect` | `#<FieldStruct::Errors empty>` or `#<FieldStruct::Errors name=["is required"]>` |
| `dup`, `clone` | a deep copy of the message arrays |

Humanizing swaps underscores for spaces and upcases the first character, nothing more. The `inspect` prefix follows [`use_alias!`](/reference/field-struct/introspection-and-tooling/).

Error keys appear in this order: first those from the defaults pass, in declaration order, then those from the input, in input order. Take three required fields `genus`, `species` and `cultivar` and the input `{cultivar: nil, genus: nil}`: the keys are `[:species, :cultivar, :genus]`.

```ruby run
errors = FieldStruct::Errors.new
errors.empty?                       # => true
errors.add(:leaf_color, 'is required')
errors.add(:base, 'Needs a second look')
errors['leaf_color']                # => ["is required"]
errors.full_messages                # => ["Leaf color is required", "Needs a second look"]
errors.to_h                         # => {leaf_color: ["is required"], base: ["Needs a second look"]}
errors.inspect                      # => '#<FieldStruct::Errors leaf_color=["is required"] base=["Needs a second look"]>'
copy = errors.dup
copy.clear(:leaf_color)
errors.empty?                       # => false
errors[:missing]                    # => []

class Label < FieldStruct::Base
  required :genus, :string
  required :species, :string
  required :cultivar, :string
end

Label.new(cultivar: nil, genus: nil).errors.to_h.keys   # => [:species, :cultivar, :genus]
```

## Errors in inspect

When there are errors, `inspect` appends them as `errors: {field: ["message"]}`. It reads them as they stand and never reruns validation or validators. Sensitive values can't show up, since messages hold no values. See [Instance API](/reference/field-struct/instance-api/).

```ruby run
Seedling.new(tag: 'zz').inspect   # => '#<Seedling tag: "zz", count: nil, stage: nil errors: {tag: ["is invalid"]}>'
```

## See also

- [Class macros](/reference/field-struct/class-macros/)
- [Exceptions](/reference/field-struct/exceptions/)
- [Validity is computed on assignment](/explanation/validity-on-assignment/)
- [Coercion versus validation](/explanation/coercion-and-validation/)
