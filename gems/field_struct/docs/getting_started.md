# Getting started

This page maps tasks to the API, explains what each error means and how to fix it, walks through one model end to
end, and lists the mistakes people make first. [USAGE.md](../USAGE.md) is the full reference.

## What do you want to do?

| Task | Use |
|---|---|
| Define a model | `class Plant < FieldStruct::Base` with `required` / `optional` / `field` |
| Read untrusted input (a form, a hash) | `Plant.new(params)`, then `valid?` and `errors` |
| Read JSON | `Plant.from_json(string)` |
| Write JSON | `plant.to_json`, or `plant.as_json` for a Hash |
| Rename keys in JSON | `serialize :json, leaves: 'leafCount'` |
| Make it raise instead of recording | `coercion_policy :raise`, `unknown_attributes :raise` |
| Make it read-only | `immutable!` (setters raise) or `frozen!` (instances frozen) |
| "Change" a read-only object | `plant.with(leaves: 300)` returns a copy |
| Check two fields against each other | `validate :method` (add to `errors[:base]`) |
| Limit values | `in:` (numbers, dates), `enum:` (strings, symbols), `format:` (strings) |
| Nest one model in another | `optional :author, Botanist` |
| A list of things | `optional :tags, :array, of: :string` |
| One of several types | `optional :tag, :union, of: %i[integer uuid]` |
| Keep a secret out of logs | `sensitive: true` |
| Add your own type | subclass `FieldStruct::Types::Base`, register it in a registry |
| See what a model accepts | `Plant.describe`, `Plant.metadata.to_h` |
| Get RBS for a model | `FieldStruct::RBS.generate(Plant)` |
| Get a model from sample JSON | `FieldStruct::Scaffold.from_json(sample)` |

## What an error means

`obj.errors.to_h` maps field names to messages. Messages never contain the value, only its class.

| Message | Meaning | Fix |
|---|---|---|
| `is required` | the field is nil, blank (strings), or empty (arrays) | send a value, or declare it `optional` |
| `is invalid` | the value was read fine but broke `format:`, `enum:` or `in:`, or a nested struct inside it is invalid | send an allowed value; for a nested struct, look at its own `errors` |
| `could not be coerced: ...` | the type could not read the value (the text after the colon says why) | send something the type can read; see the type's row in USAGE |
| `element at index 2 is invalid` | an array element broke the `element:` options | fix those elements |
| `could not be coerced: element at index 1: ...` | an array element could not be read | fix that element |

Raised errors, when a policy asks for them:

| Exception | When | Look at |
|---|---|---|
| `FieldStruct::CoercionError` | `coercion_policy :raise` and a value could not be read | `field_name`, `original` |
| `FieldStruct::UnknownAttributeError` | `unknown_attributes :raise` and a key matched no field | `keys` |
| `FieldStruct::ImmutableError` | a setter was called on an `immutable!` object | use `with` |
| `ArgumentError` at class definition | a bad declaration (unknown type, bad option, reserved name) | the message names the field and the fix |
| `EncodingError` from `from_json` | malformed JSON | check the source |
| `ArgumentError` from `from_json` | the JSON root isn't an object | send an object |

## One model, start to finish

<!-- doctest -->
```ruby
require 'field_struct'

class Botanist < FieldStruct::Base
  required :name, :string
  optional :born, :date, format: :iso8601
end

class Plant < FieldStruct::Base
  required :species,  :string
  required :accession,   :string, format: /\AACC-\d{5}\z/
  optional :leaves,  :integer, in: 1..5000
  optional :yield_kg,  :decimal, round: 2
  optional :author, Botanist
  optional :tags,   :array, of: :string
  optional :kind,   :symbol, enum: %i[shrub climber], default: :shrub
  serialize :json, accession: 'TAG'

  validate :heavy_plants_need_a_yield

  def heavy_plants_need_a_yield
    errors.add(:base, 'Plants over 1000 leaves need a yield_kg') if leaves && leaves > 1000 && yield_kg.nil?
  end
end

# 1. Build from untrusted input and look at the result.
plant = Plant.new(species: 'Monstera', accession: 'ACC-20931', leaves: '412', yield_kg: '9.999',
                author: {name: 'Maria Merian', born: '1647-04-02'})
plant.valid?                 # => true
plant.yield_kg.to_s('F')        # => "10.0"
plant.author.born.year       # => 1647

# 2. Bad input is kept, flagged, and explained.
bad = Plant.new(species: '', accession: '123', leaves: 2000)
bad.errors.to_h.keys        # => [:species, :accession, :base]
bad.errors.full_messages.last   # => "Plants over 1000 leaves need a yield_kg"

# 3. JSON uses the mapped names, both ways.
json = plant.to_json
json.include?('"TAG":"ACC-20931"')   # => true
Plant.from_json(json) == plant              # => true

# 4. Describe it.
puts Plant.describe.lines.first
```

## Mistakes people make first

1. **Expecting setters to raise.** They don't. `plant.leaves = 'many'` stores `'many'` and adds an error. Check `valid?`,
   or set `coercion_policy :raise` on the class.
2. **Reading "required" as "never nil".** Required means `valid?` fails when the value is missing. A fresh object with a
   required field unset is allowed to exist; its reader returns `nil`. Whitespace-only strings and empty arrays count as
   missing.
3. **Forgetting `of:`.** `:array` and `:union` need it, and the declaration raises without it.
4. **Putting options on the wrong type.** `round:` belongs to numbers, `format:` to strings and dates, `enum:` to strings
   and symbols. The error lists where the option does apply. Options for an element go in `element: {...}`, not on the
   field.
5. **Putting cross-field rules in a field.** Use `validate` and add to `errors[:base]`.
6. **Using the standard library JSON.** `to_json` and `from_json` go through Oj. Call them; don't `JSON.generate` the
   object.
7. **Ignoring unknown keys.** By default extra input keys are dropped without a word. Use `unknown_attributes :raise`
   if a typo should fail loudly.
8. **Logging values and expecting masks.** Messages never echo values, but `inspect` does show them unless the field is
   `sensitive: true`.
9. **Reading stale validity.** Validity is computed when you assign. Changing a nested object or an array element in
   place doesn't refresh the parent. Re-assign it, or use `with`.
10. **Passing a Hash to `with`.** It takes keywords: `plant.with(**changes)`, not `plant.with(changes)`.

## Rails

field_struct doesn't need Rails and never requires ActiveSupport. It behaves the same with ActiveSupport loaded. Some
specifics:

- **Params.** Pass permitted parameters straight in: `Plant.new(params.require(:plant).permit(:species, :leaves))`. Anything
  that responds to `to_hash` works, with String or Symbol keys. Pass `unknown_attributes :raise` to the class if you'd
  rather fail on extra keys than drop them.
- **Naming.** `Plant.model_name` and `plant.to_model` exist, so form builders and URL helpers can name the class. A struct
  is not an Active Model object: it has no persistence methods and no `ActiveModel::Validations`. `valid?` and `errors`
  are field_struct's own; `errors.full_messages` returns Strings.
- **JSON.** `render json: plant` works: `as_json` ignores its options and returns every field.
- **Time zones.** `zone:` takes IANA names (`America/Denver`), `UTC` or an offset, not Rails names like
  `"Mountain Time (US & Canada)"`. Give it `ActiveSupport::TimeZone::MAPPING['Mountain Time (US & Canada)']` if you hold a
  Rails name. Values come back as plain `Time` or `DateTime`, not `TimeWithZone`.
- **Load order.** Require ActiveSupport before or after the gem; nothing in field_struct depends on what it redefines.
