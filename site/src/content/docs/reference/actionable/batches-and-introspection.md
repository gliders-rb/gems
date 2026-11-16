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

The action runs once per item, in order, and each run is independent of the others. You get back a `BatchResult` that keeps the same order. The block turns an item into run arguments: a Hash becomes keywords, an Array becomes positional arguments, and anything else is one positional argument. With no block, items follow that same rule. One item failing never affects another, and nothing wraps the whole batch in a transaction.

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

## Descriptions

`desc 'text'` in the class body describes the action in prose; `description` is the same macro, and either one reads it back with no argument. A class gets one description (a second raises `DefinitionError`), and a subclass doesn't inherit it. `desc:` describes a step, a `case_step`, a branch, a hook or a `fails`/`skips` code, and must be a String. On `fails` and `skips` it never becomes metadata, so it can't reach a result's `to_h` or `as_json`. A run never reads any of it; `describe` carries it, for people and for docs.

```ruby run
class SharpenSaw < Actionable::Action
  desc 'Files every tooth of a hand saw back to an edge.'

  fails :tooth_broken, retry: false, desc: 'A tooth snapped off while filing'
  step :clamp_blade, desc: 'Clamp the blade in the saw vice'

  private

  def clamp_blade = nil
end

SharpenSaw.desc                                  # => "Files every tooth of a hand saw back to an edge."
SharpenSaw.description                           # => "Files every tooth of a hand saw back to an edge."
SharpenSaw.declared_failures                     # => {tooth_broken: {retry: false}}
SharpenSaw.describe[:description]                # => "Files every tooth of a hand saw back to an edge."
SharpenSaw.describe[:steps].first[:description]  # => "Clamp the blade in the saw vice"
```

## `describe`

```ruby
Action.describe # => Hash
```

The Hash `describe` returns has exactly eleven keys.

| Key | Value |
|---|---|
| `name` | the class name, or `nil` when anonymous |
| `description` | the action's `desc`, or `nil` |
| `input` | the input schema's `metadata.to_h`; `{discriminated_on:, shapes:}` for a dispatched action; `nil` when free-form |
| `output` | the output schema's `metadata.to_h`, or `nil` |
| `steps` | step entries `{type:, name:, options:, description:}`; `type` is `:method`, `:action` or `:case`; an action step's `name` is the class; `options` leaves out `desc:`, which is `description`; plus `guard:` when guarded and, on a case step, `branches:` and `default:` (below) |
| `failures`, `skips` | `{code => {message:, metadata:, description:}}`, plus `output:` when the code has a schema |
| `hooks` | `{on_success:, on_failure:, on_skip:, always:}`, each a list of step entries |
| `measure` | the mode Symbol |
| `transactional` | the transaction config, or `nil` |
| `calls` | the actions its methods run by hand (`Child.run` in a step, hook or a helper they call), found in the source; `[]` when none |

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
description.keys.size                # => 11
description[:name]                   # => "Sounding"
description[:steps]                  # => [{type: :method, name: :lower_line, options: {}, description: nil}]
description[:hooks][:always]         # => [{type: :method, name: :coil_line, options: {}, description: nil}]
description[:failures]               # => {aground: {message: "keel touched bottom", metadata: {retry: true}, description: nil}}
description[:input].keys             # => [:berth]
description[:output]                 # => nil
description[:measure]                # => :none
description[:transactional]          # => nil
description[:calls]                  # => []
```

### Guards, branches and defaults

A guarded entry, step or hook, has `guard:` with a label for each of `if:` and `unless:`. A Symbol or String guard gives its method name. A callable gives its own `desc` when it responds to `desc` with a String, and `"a custom condition"` otherwise. Entries without a guard have no `guard:` key. A case step's entry adds `branches:`, one `{on:, step:}` per branch in order (`on` is the match value as you wrote it, an Array for `on %w[a b]`), and `default:`, the default's entry or `nil`.

```ruby run
class StowGear < Actionable::Action
  step :coil_rope, if: :rope_wet?
  step :lock_shed, unless: ->(action) { false }

  case_step :gear do
    on 'oar', :rack_oars
    on %w[sail jib], :fold_sail, desc: 'Fold it dry'
  end

  on_failure :report_loss, if: :something_missing?

  private

  def rope_wet? = true
  def something_missing? = false
  def gear = 'oar'
  def coil_rope = nil
  def lock_shed = nil
  def rack_oars = nil
  def fold_sail = nil
  def report_loss = nil
end

steps = StowGear.describe[:steps]
steps[0][:guard]                              # => {if: "rope_wet?"}
steps[1][:guard]                              # => {unless: "a custom condition"}
steps[2][:branches].map { |branch| branch[:on] }   # => ["oar", ["sail", "jib"]]
steps[2][:branches].last[:step][:description]      # => "Fold it dry"
steps[2][:default]                            # => nil
StowGear.describe[:hooks][:on_failure].first[:guard]   # => {if: "something_missing?"}
```

`calls` is read from the source with Prism, not from a run: a `run` or `run!` on a constant that names an action, in a step, a hook, or one of the class's own methods they call. A receiver held in a variable isn't seen, and neither is an action defined in irb or by `eval`, which has no source file to read (so this example is shown, not run).

```ruby
class Restock < Actionable::Action
  step :order_more

  private

  def order_more
    Sounding.run(berth: 'dock 2')
  end
end

Restock.describe[:calls]           # [Sounding]
Restock.describe_text.lines.last   # "  Calls: Sounding (found in source)"
```

## `describe_text`

`describe_text` prints those same facts as a multi-line String, with no trailing newline:

1. `<name or "action"> (measure: <mode>)`, with `, transactional` after the mode when a transaction config exists.
2. `  Input:` followed by ` (free-form)`, or ` (discriminated on <name>: <variants>)`, or the schema's field lines indented two extra spaces.
3. `  Output:` the same way.
4. `  Steps:` and one `    - <name> (<kind>)` line per step, or `    (none)`.
5. `  Failures:` and `  Skips:`, only when non-empty, one `    - <code>` line each, with the metadata in parentheses and `: <message>` when there is one.
6. `  Hooks:`, only when some list is non-empty, one `    <section>: <names>` line per non-empty section.
7. `  Calls: <names> (found in source)`, only when `calls` is non-empty.

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
