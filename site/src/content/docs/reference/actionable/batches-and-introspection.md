---
title: "Batches and introspection"
description: "Run an action over many items with run_each, look actions up in the registry, and describe an action as data or text."
sidebar:
  order: 7
---

Three tools here treat actions as data. `run_each` feeds many inputs to one action, `Actionable.registry` finds an action by name, and `describe` reads an action's shape without running it.

## `run_each`

```ruby
Action.run_each(items) { |item| args } # => BatchResult
```

The action runs once per item, in order, and each run is independent of the others. You get back a `BatchResult` that keeps the same order. The block turns an item into run arguments: a Hash becomes keywords, an Array becomes positional arguments, and anything else is one positional argument. With no block, items follow that same rule. One item failing never affects another, and nothing wraps the whole batch in a transaction (AC-B#runeach).

```ruby run
class TrimLoad < Actionable::Action
  input { required :cars, :integer }
  output { required :axles, :integer }
  fails :uneven

  step :weigh

  private

  def weigh
    fail!(:uneven) if input.cars.odd?
    @axles = input.cars * 3
  end
end

batch = TrimLoad.run_each([5, 6, 7, 8]) { |cars| { cars: cars } }
batch.size                     # => 4
batch.all_ok?                  # => false
batch.any_failure?             # => true
batch.partial?                 # => true
batch.successes.map(&:axles)   # => [18, 24]
batch.failures.size            # => 2
batch.skips.size              # => 0
batch[0].code                  # => :uneven
batch[7]                       # => nil
batch.map(&:status)            # => [:failure, :success, :failure, :success]
batch.to_api_h(id_field: :axles).first # => {index: 0, status: :failure, id: nil, errors: {}}
```

### `BatchResult`

`BatchResult` includes Enumerable over its results, and `each` with no block gives you an enumerator.

| Method | Returns |
|---|---|
| `[]` | the result at an index, `nil` out of range |
| `size`, `length`, `results` | the count, and the results |
| `empty?` | true with no results |
| `all_ok?` | true when every result is `ok?` (vacuously true when empty) |
| `any_failure?` | true when any result is a failure |
| `partial?` | `any_failure?` and at least one ok result; false when empty or all failed |
| `successes`, `failures`, `skips` | results selected by outcome |
| `to_api_h(id_field: :id)` | `result.to_api_h(index: i, id_field:)` for each result, in order |

## The registry

`Actionable.registry` is one `Registry` per process. A named subclass lands in it the moment it is created. `Registry#register` overwrites whatever class already holds the name, skips anonymous classes, and returns the registry. Registration happens at subclass creation, so a `Class.new(Action)` you name later never gets in. Entries are never removed, and the registry takes no lock.

| Method | Returns |
|---|---|
| `[]` | the class for a String or Symbol name, `nil` if unknown |
| `keys`, `values`, `size`, `empty?` | the usual |
| `each` | yields `(name, class)`, or an enumerator without a block |
| `register(klass)` | the registry |

```ruby run
class Pilotage < Actionable::Action; end

registry = Actionable.registry
registry[:Pilotage]               # => Pilotage
registry['Pilotage']              # => Pilotage
registry['Unmoored']              # => nil
registry.keys.include?('Pilotage') # => true
registry.values.include?(Pilotage) # => true
registry.empty?                   # => false
registry.register(Class.new(Actionable::Action)).equal?(registry) # => true
registry.each.first.class         # => Array
```

## `describe`

```ruby
Action.describe # => Hash
```

The Hash `describe` returns has exactly nine keys.

| Key | Value |
|---|---|
| `name` | the class name, or `nil` when anonymous |
| `input` | the input schema's `metadata.to_h`; `{discriminated_on:, shapes:}` for a dispatched action; `nil` when free-form |
| `output` | the output schema's `metadata.to_h`, or `nil` |
| `steps` | `[{type:, name:, options:}]`; `type` is `:method`, `:action` or `:case`; an action step's `name` is the class |
| `failures`, `skips` | `{code => {message:, metadata:}}`, plus `output:` when the code has a schema |
| `hooks` | `{on_success:, on_failure:, on_skip:, always:}` as name lists |
| `measure` | the mode Symbol |
| `transactional` | the transaction config, or `nil` |

On a dispatched action, `shapes` lists the values each branch matches on, not the schema classes the name might suggest. Load the Rails adapter and `hooks` also carries an `after_commit` key, there even when empty.

```ruby run
class Sounding < Actionable::Action
  input { required :berth, :string }
  fails :aground, 'keel touched bottom', retry: true
  skips :slack
  step :lower_line
  always :coil_line

  private

  def lower_line = nil
  def coil_line = nil
end

description = Sounding.describe
description.keys.size                # => 9
description[:name]                   # => "Sounding"
description[:steps]                  # => [{type: :method, name: :lower_line, options: {}}]
description[:hooks][:always]         # => [:coil_line]
description[:failures]               # => {aground: {message: "keel touched bottom", metadata: {retry: true}}}
description[:input].keys             # => [:berth]
description[:output]                 # => nil
description[:measure]                # => :none
description[:transactional]          # => nil
```

## `describe_text`

`describe_text` prints those same facts as a multi-line String, with no trailing newline:

1. `<name or "action"> (measure: <mode>)`, with `, transactional` after the mode when a transaction config exists.
2. `  Input:` followed by ` (free-form)`, or ` (discriminated on <name>: <variants>)`, or the schema's field lines indented two extra spaces.
3. `  Output:` the same way.
4. `  Steps:` and one `    - <name> (<kind>)` line per step, or `    (none)`.
5. `  Failures:` and `  Skips:`, only when non-empty, one `    - <code>` line each, with the metadata in parentheses and `: <message>` when there is one.
6. `  Hooks:`, only when some list is non-empty, one `    <section>: <names>` line per non-empty section.

The field lines are FieldStruct's own description, so they change with its version.

```ruby run
lines = Sounding.describe_text.lines.map(&:chomp)
lines.first                    # => "Sounding (measure: none)"
lines.include?('  Steps:')     # => true
lines.include?('    - lower_line (method)') # => true
lines.include?('    - aground (retry: true): keel touched bottom') # => true
lines.last                     # => "    always: coil_line"
```

## See also

- [Results](/reference/actionable/results/): `to_api_h` and the result shape
- [Declared outcomes](/reference/actionable/declared-outcomes/): what `failures` and `skips` list
- [Introspection and tooling](/reference/field-struct/introspection-and-tooling/): `metadata.to_h` for the schemas
