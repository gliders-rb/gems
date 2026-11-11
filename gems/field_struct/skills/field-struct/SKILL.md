---
name: field-struct
description: Define, debug and type Ruby models built with the field_struct gem (typed plain objects with coerced, validated fields). Use when writing or changing a class that inherits FieldStruct::Base, reading its errors, or generating RBS for it.
when_to_use: The code requires 'field_struct', a class inherits FieldStruct::Base, or the user asks for typed Ruby value objects with declared fields, coercion and validation errors.
---

# field_struct

A model is a class that inherits `FieldStruct::Base` and declares fields. Every assignment coerces the value and records
errors; nothing raises unless the class says so.

The full reference ships with the gem. Read `USAGE.md` once before writing a model (`bundle exec gem contents field_struct | grep USAGE.md`,
or `bundle info field_struct` for the path). `docs/getting_started.md` has the task map and the error table.

## Define a model

1. List the fields and decide which are `required` (must be present) and which are `optional`.
2. Pick a type for each: `:string`, `:integer`, `:float`, `:decimal`, `:boolean`, `:symbol`, `:date`, `:time`,
   `:datetime`, `:uuid`, `:url`, `:email`, `:binary`, `:value` (anything), `:array` (needs `of:`), `:union` (needs `of: [...]`),
   or another struct class for a nested field.
3. Add the options the type takes: `format:`, `enum:`, `in:`, `round:`, `base:`, `strict:`, `values:`, `zone:`,
   `element:`. Universal ones: `default:`, `coercion_policy:`, `description:`, `rbs_type:`, `sensitive:`.
4. Add class settings if needed: `unknown_attributes :raise`, `coercion_policy :raise`, `immutable!`, `frozen!`.
5. Add cross-field rules with `validate :method` (add messages to `errors[:base]`).
6. Add `serialize :json, field: 'externalName'` if the JSON names differ.
7. Check it: `Model.describe`, then build one from sample input and read `valid?` and `errors.to_h`.

```ruby
class Plant < FieldStruct::Base
  required :species, :string
  optional :leaves, :integer, in: 1..5000
  optional :tags,  :array, of: :string
end
```

## Common mistakes

- Expecting setters to raise. They store the raw value and record an error. Check `valid?`.
- Treating `required` as "never nil". An unset required field reads as `nil`; `valid?` is what fails.
- Whitespace-only strings and empty arrays are missing.
- Leaving out `of:` on `:array` or `:union`.
- Putting an option on a type that doesn't take it (`round:` on a string). The error lists the types that do.
- Putting element options on the field instead of in `element: {...}`.
- Putting cross-field rules anywhere but `errors[:base]` via `validate`.
- Using stdlib JSON on a struct. Use `to_json`, `as_json`, `from_json` (Oj).
- Forgetting unknown keys are ignored unless `unknown_attributes :raise`.
- Mutating a nested object in place and expecting the parent's validity to update. Re-assign it or use `with`.
- Calling `with(hash)`. It takes keywords: `with(**hash)`.

## Debug an invalid instance

Read `obj.errors.to_h` (Symbol field to Array of Strings). Messages never contain the value, only its class.

- `"is required"`: the field is nil, blank or empty. Send a value or make it `optional`.
- `"is invalid"`: the value was read but broke `format:`, `enum:` or `in:`, or a nested struct inside it is invalid.
- `"could not be coerced: ..."`: the type couldn't read the value; the text after the colon says why.
- `"element at index N ..."`: an array element is the problem; the index is 0-based.

The raw input stays in the reader, so `obj.field` shows what was sent. Under `coercion_policy :replace` it is `nil`.

## Extend with a custom type

Subclass `FieldStruct::Types::Base`; implement `coerce(value, **options)` (raise `ArgumentError`, `TypeError` or
`RangeError` for unreadable input) and `ruby_type`. Register it in a registry:

```ruby
module Nursery
  def self.field_types
    @field_types ||= FieldStruct.new_registry { register :cents, Cents }
  end
end
```

Structs inside `Nursery` can then say `required :yield_kg, :cents`. Add `rbs_type` to the type to control its RBS.

## Type models with RBS

`FieldStruct::RBS.generate(Model)` returns RBS for a model: readers of required fields have no `?`, writers accept
`nil`, scalar array elements are nullable. The types describe a valid instance, so check `valid?`. Override a field with
`rbs_type: '::Pathname'`. The gem's own signatures are in `sig/field_struct.rbs`.

## Upgrade

1. Read `CHANGELOG.md` from your version to the new one.
2. Update the gem and run your suite.
3. Regenerate model signatures with `FieldStruct::RBS.generate` and review the diff.
4. If a model fails a declaration check (`ArgumentError` at class definition), the message names the field and the fix.
