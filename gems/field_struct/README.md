# field_struct

Typed plain Ruby objects. You declare a field's name, type and options. Every assignment coerces the value, records
what's wrong with it, and leaves the object usable. Nothing raises just because the input was bad.

```ruby
gem 'field_struct', '~> 1.0.0.pre1'
```

It's a pre-release, so the constraint names the pre-release version. Ruby 3.3 or newer. Runtime dependencies: `oj`, `bigdecimal`, `tzinfo`. ActiveSupport and ActiveModel are never required.

## A first model

```ruby run
require 'field_struct'

class Plant < FieldStruct::Base
  required :species, :string
  optional :leaves, :integer, in: 1..5000
  optional :tags,  :array, of: :string
end

plant = Plant.new(species: 'Monstera', leaves: '412', tags: %w[tropical shade])
plant.leaves          # => 412
plant.valid?          # => true
plant.to_h            # => {species: "Monstera", leaves: 412, tags: ["tropical", "shade"]}
plant.to_json         # => '{"species":"Monstera","leaves":412,"tags":["tropical","shade"]}'

bad = Plant.new(species: '  ', leaves: 'many')
bad.valid?                       # => false
bad.leaves                       # => "many"
bad.errors.to_h[:species]        # => ["is required"]
bad.errors.full_messages.first   # => "Species is required"
```

Bad input doesn't raise. It's recorded, and the raw value stays where it was assigned. That's the whole model: assign
anything, read back the coerced value, and ask `valid?` when you care.

Types (strings, numbers, booleans, dates and times with zones, arrays, maps, nested structs, unions, your own), JSON in and
out, policies, cross-field rules, introspection and generated RBS are all in the reference.

## Where to go next

- [The docs site](https://gliders-rb.github.io/): a tutorial, how-to guides and the full reference, with every example run in CI.
- [USAGE.md](USAGE.md): the reference, example first.
- [docs/getting_started.md](docs/getting_started.md): which API for which task, what each error means, common mistakes, Rails.
- [CHANGELOG.md](CHANGELOG.md)
- [AGENTS.md](AGENTS.md): short guide for coding agents.

MIT licensed.
