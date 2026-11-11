---
title: "Input and output"
description: "Declaring typed input and output with FieldStruct, dispatching input by a discriminator, and the failures the gem builds itself."
sidebar:
  order: 4
---

Input and output of an action are both FieldStruct schemas: the input is checked before the first step, the output after the last. Types come from the system described on [FieldStruct's types page](/reference/field-struct/types/). The gem produces two failures on its own, `:invalid_input` and `:invalid_output`, and below we say when each appears.

## `input`

```ruby
input { |schema_body| ... } # declare
input                       # read the schema class, or nil
```

The block holds a FieldStruct body. `Action.input_schema` reads the same thing, `Action.input.new(...)` makes an instance, and a subclass shares the schema of its parent. If the action has no `input`, both the class reader and the step-side `input` return `nil` (AC-B#inputnoblock).

`.run(**kwargs)` builds the struct from the keywords (string keys are fine), checks `valid?` and gives the steps the struct as `input`. Values get coerced, so `bunks: '12'` turns into `12`. Keywords the schema doesn't know are dropped, except under `unknown_attributes :raise`, where `.run` raises `FieldStruct::UnknownAttributeError` itself and no failure is returned.

```ruby run
class FillDeck < Actionable::Action
  input do
    required :bunks, :integer
    optional :remark, :string
  end

  step :load

  private

  def load = succeed("filled #{input.bunks}")
end

FillDeck.run(bunks: '12').message   # => "filled 12"
bad = FillDeck.run(remark: 'x')
bad.code                         # => :invalid_input
bad.message                      # => "input failed validation"
bad.errors.to_h                  # => {bunks: ["is required"]}
bad.output                       # => {}
FillDeck.input_schema.attribute_names # => [:bunks, :remark]
FillDeck.input.equal?(FillDeck.input_schema) # => true
```

With invalid input, no step runs. The failure holds the struct's errors, an empty output and whatever metadata was declared for `:invalid_input` (AC-B#invalidinput). An invalid nested struct field reports just the field name with `"is invalid"`.

:::caution
One positional argument that is already an instance of the input schema is taken as is. Any other positional argument, a Hash too, is dropped without a word, and the run ends `:invalid_input` with "is required" on every required field. Splat your hashes: `.run(**params)`.
:::

## `input_for`

```ruby
input_for(discriminator) { on(match, SchemaClass); default(SchemaClass) }
```

`input_for` chooses the schema at run time, looking at a single keyword. `on` accepts a value, an Array of values or a Regexp. The first branch that matches in declaration order wins and `default` comes last. Matching works exactly as in case steps (see [Actions and steps](/reference/actionable/actions-and-steps/#case_step)), and the chosen schema is built and validated like a fixed input. If both `input` and `input_for` are declared, the dispatch has the final say.

```ruby run
class FreightShape < FieldStruct::Base
  required :bunks, :integer
end

class RebateShape < FieldStruct::Base
  required :voyage_no, :integer
end

class LogManifest < Actionable::Action
  input_for(:manifest_kind) do
    on 'freight', FreightShape
    on %w[rebate refund], RebateShape
  end

  step :log

  private

  def log = succeed(input.class.name)
end

LogManifest.run(manifest_kind: 'freight', bunks: 5).message     # => "FreightShape"
LogManifest.run(manifest_kind: 'rebate', voyage_no: 1).message  # => "RebateShape"
LogManifest.run(manifest_kind: 'kraken').message                # => "no input shape for manifest_kind \"kraken\""
LogManifest.run(manifest_kind: 'kraken').code                   # => :invalid_input
```

If nothing matches and there is no `default`, the result is `Failure(:invalid_input)` with the message `no input shape for <discriminator> <value.inspect>`. An absent discriminator is read as `nil`. It is looked up by Symbol in the keywords only, so a string key such as `'manifest_kind'` finds nothing. One positional instance of any schema the dispatch can reach is accepted as is.

`Action.input_dispatch` is an `InputDispatch` (`nil` without `input_for`):

| Member | Returns |
|---|---|
| `discriminator` | the Symbol |
| `branches` | `[match_value, schema]` pairs in order |
| `variants` | the match values in order; `%w[rebate refund]` stays one entry |
| `schemas` | the distinct schema classes, branches then default |
| `default_schema` | the `default` schema, or `nil` |
| `schema_for(value)` | the first matching schema, else the default, else `nil` |

```ruby run
dispatch = LogManifest.input_dispatch
dispatch.discriminator         # => :manifest_kind
dispatch.variants              # => ["freight", ["rebate", "refund"]]
dispatch.schema_for('refund')  # => RebateShape
dispatch.schemas               # => [FreightShape, RebateShape]
dispatch.branches.first        # => ["freight", FreightShape]
dispatch.default_schema        # => nil
```

`input_for` is a thin wrapper over `InputDispatch.define(discriminator) { ... }`, whose builder offers `on` and `default`. For a dispatched action the generated RBS types `.run` as `(*untyped)` (see [RBS](/reference/actionable/rbs/)).

## `output`

```ruby
output { |schema_body| ... } # declare
output                       # read the schema class, or nil
```

Nothing but the fields declared in `output` reaches the result (AC-I5). Once the steps are done, and again after each hook, each declared field is filled from the instance variable with the same name (a variable holding `nil` still counts as set). Keywords given to `succeed` beat variables, and the struct is then coerced and validated. Variables and keywords that were never declared are left out. A valid struct becomes `result.output`, and its fields can be read straight off the result (see [Results](/reference/actionable/results/#output-delegation)).

When a success can't satisfy its output schema, it is swapped for `Failure(:invalid_output)`: the message is `output failed validation`, the field errors come from the struct, and the invalid struct stays available as `output` for inspection. Later hooks keep that invalid output instead of rebuilding it. Only a strict success is validated against the success schema (AC-B#invalidout).

```ruby run
class SettleFare < Actionable::Action
  output { required :fare_pence, :integer }

  step :settle

  private

  def settle
    @fare_pence = nil
    @scratch = 'never shown'
  end
end

result = SettleFare.run
result.code                 # => :invalid_output
result.errors.to_h          # => {fare_pence: ["is required"]}
result.output.valid?        # => false
SettleFare.output_schema.attribute_names # => [:fare_pence]
```

Keywords beat variables, and the schema coerces the values:

```ruby run
class CountDecks < Actionable::Action
  output do
    required :decks, :integer
    required :tag, :string
  end

  step :count

  private

  def count
    @decks = '2'
    @tag = 7
    succeed(decks: 4)
  end
end

CountDecks.run.decks # => 4
CountDecks.run.tag   # => "7"
```

With no output schema the output is whatever `succeed` received (a Hash, `{}` if nothing), and fields are not delegated. A failure or skip grabs the declared variables that were set up to that point, as a best effort, without validating and without adding an `output` error. A failure code with its own schema is built from the keywords it was given and nothing else (see [Declared outcomes](/reference/actionable/declared-outcomes/)). A hook that sets a variable named like an output field is picked up by the next refresh, which means a hook can break an output that was valid before (AC-B#hookoutput).

### Reserved output names

Output fields can't share a name with a result attribute (`code`, `message`, `output`, `history`, `errors`, `metadata`), a reserved action name (`result`, `input`) or any public Result method (`status`, `ok?`, `to_h`, `output_fields_set`, `absorb_errors_from`, and so on). Declaring one raises `Actionable::DefinitionError` right away: Result methods always win, so the gem refuses any ambiguity. Input field names aren't guarded, because they are read as `input.x`.

```ruby run
begin
  Class.new(Actionable::Action) { output { required :status, :string } }
rescue Actionable::DefinitionError => e
  e.message.include?(':status') # => true
end
```

## See also

- [Declared outcomes](/reference/actionable/declared-outcomes/): per-code output schemas
- [FieldStruct types](/reference/field-struct/types/): what you can declare inside the block
- [Results](/reference/actionable/results/): `output_fields_set` and delegation
