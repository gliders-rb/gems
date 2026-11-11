---
title: "Declared failures, skips and typed outcomes"
description: "Announce the codes an action can end with, attach messages and metadata, and give each code its own output."
sidebar:
  label: "Declared outcomes"
  order: 5
---

With `fails` and `skips` an action lists the codes it can end with. That list is a contract: as soon as one code is declared, only declared codes are allowed (AC-I7). The core stores and shows the metadata but never interprets it, and the job adapter is the single reader, and only after an explicit opt-in. Typed outcomes take it a step further by giving each code its own output and result class.

## `fails` and `skips`

```ruby
fails(code, message = nil, **metadata, &output_schema)
skips(code, message = nil, **metadata, &output_schema)
```

Both keep `{message:, metadata:}` under the code (a Symbol or String, turned into a Symbol), and the metadata is frozen. Any failure or skip ending with that code exposes the metadata as `result.metadata`, plus the declared message when the call passed none, since an explicit message always wins. Subclasses get a copy of the declarations and may add to them or redeclare. A redeclaration replaces message, metadata and schema together, so leaving out the block drops the parent's schema.

```ruby run
class HoldBerth < Actionable::Action
  fails :deck_full, 'no berth free on this deck', retry: false
  fails :harbour_closed, retry: true
  skips :already_held

  step :hold

  private

  def hold = fail!(:deck_full)
end

result = HoldBerth.run
result.message  # => "no berth free on this deck"
result.metadata # => {retry: false}
HoldBerth.declared_failures # => {deck_full: {retry: false}, harbour_closed: {retry: true}}
HoldBerth.declared_skips    # => {already_held: {}}
HoldBerth.failure_declarations[:deck_full] # => {message: "no berth free on this deck", metadata: {retry: false}}
HoldBerth.skip_declarations.keys           # => [:already_held]
```

| Reader | Returns |
|---|---|
| `declared_failures`, `declared_skips` | `{code => metadata}` |
| `failure_declarations`, `skip_declarations` | `{code => {message:, metadata:}}`, plus `:output_schema` when the declaration had a block |
| `failure_output_schema(code)`, `skip_output_schema(code)` | the code's schema class, or `nil` |
| `allows_failure_code?(code)` | true when no failures are declared, the code is declared, or it is a gem code |
| `allows_skip_code?(code)` | true when no skips are declared or the code is declared |

## Strictness

Declare one failure code and the action may only fail with declared codes, plus the gem's own `:invalid_input` and `:invalid_output`. Every other `fail`, `fail!`, `fail_with` or `fail_with!` raises `DefinitionError` at the call, and that includes the default `:invalid` of `fail_with`. Skips obey the same rule with no exceptions, since the gem emits no skip codes of its own: once a skip is declared, even the implicit `:skipped` of a bare `skip!` needs a declaration. Declaring failures doesn't make skips strict, nor the reverse, and an action declaring neither is unchecked. A failure adopted from a nested child gets the same check (AC §5.9).

```ruby run
class CastOff < Actionable::Action
  fails :moored

  step :untie

  private

  def untie = fail!(:other)
end

begin
  CastOff.run
rescue Actionable::DefinitionError => e
  e.message # => "CastOff fails with :other, which it does not declare; declare it with `fails :other` (declared: :moored)"
end

CastOff.allows_failure_code?('moored')         # => true
CastOff.allows_failure_code?(:invalid_input)   # => true
CastOff.allows_failure_code?(:other)           # => false
CastOff.allows_skip_code?(:whatever)           # => true
```

`fail` checks in this order: first that the code is an identifier, then that it is declared, and with typed outcomes the output checks come last.

### Gem codes

`:invalid_input` and `:invalid_output` are allowed at all times. Declaring either one only puts metadata on the failures the gem builds, and when they occur stays the same. Neither takes an output schema, so a block on them raises `ArgumentError` at declaration.

```ruby run
class ReadSignal < Actionable::Action
  input { required :flags, :string }
  fails :invalid_input, 'garbled signal', retry: false

  step :read

  private

  def read = succeed
end

ReadSignal.run.metadata # => {retry: false}
ReadSignal.run.message  # => "input failed validation"
```

## Per-code output schemas

Give `fails` or `skips` a block and it becomes that code's output schema, using the same DSL and the same reserved-name check as `output`. A result carrying such a code is assembled from the keywords it received and never from instance variables, then coerced and validated as a success is. If the output breaks the schema, the run ends as `Failure(:invalid_output)`. The block is an opt-in of its own, so all this holds with or without typed outcomes.

For a failure code that has a schema, `fail`, `fail!`, `fail_with` and `fail_with!` receive the output through the `output:` keyword, as a Hash or a FieldStruct, and never as an error key. A skip receives it as keywords, like `succeed`.

```ruby run
class BookCabin < Actionable::Action
  input { required :bunks, :integer }
  fails(:deck_full) { required :free_bunks, :integer }

  step :allocate

  private

  def allocate = fail!(:deck_full, 'not enough bunks', output: { free_bunks: 2 })
end

result = BookCabin.run(bunks: 5)
result.code              # => :deck_full
result.output.free_bunks # => 2
BookCabin.failure_output_schema(:deck_full).attribute_names # => [:free_bunks]
```

## Typed outcomes

```ruby
typed_outcomes                  # turn on
typed_outcomes(enabled: false)  # turn off
typed_outcomes?                 # read
```

Turn typed outcomes on and `.run` hands back the action's own `Success`, `Failure` and `Skipped` classes. They live as constants inside the action and inherit from the gem's classes, so `is_a?(Actionable::Failure)` keeps working. When the parent action has typed outcomes, they inherit from the parent's classes instead. The flag is copied as a snapshot, and a subclass can switch it off for itself. If the action already defines a constant named `Success`, `Failure` or `Skipped`, enabling the flag raises `DefinitionError`.

Each code has a contract of its own. A failure or skip whose code has no schema carries `{}` as output, no matter what the steps left behind, and passing non-empty output raises `DefinitionError` at the call. An empty Hash is fine, and an `output:` that is neither a Hash nor a FieldStruct raises `ArgumentError`. The gem's own failures are exempt: `invalid_output` carries the invalid struct and `invalid_input` always has `{}`.

```ruby run
class ChartRoute < Actionable::Action
  typed_outcomes

  input { required :leagues, :integer }
  output { required :hours, :integer }

  fails(:too_far) { required :range_leagues, :integer }

  step :plan

  private

  def plan
    fail!(:too_far, output: { range_leagues: 40 }) if input.leagues > 40
    @hours = input.leagues * 2
  end
end

ok = ChartRoute.run(leagues: 12)
ok.class     # => ChartRoute::Success
ok.hours     # => 24

failure = ChartRoute.run(leagues: 90)
failure.class                          # => ChartRoute::Failure
failure.range_leagues                  # => 40
failure.is_a?(Actionable::Failure)     # => true
ChartRoute.typed_outcomes?             # => true
```

Equality goes by class, so with typed outcomes `ChartRoute.run(leagues: 12) == Actionable::Success.new(...)` is false, and you compare against the action's own class instead. When a child's failure crosses into a typed parent, it turns into the parent's own `Failure`, judged by the parent's schema for that code. The parent still has to declare the code, and output that breaks the parent's schema ends the parent as `invalid_output`. A parent without typed outcomes receives a plain `Actionable::Failure`. The gem's two own codes cross with their output as it was (AC §5.10).

:::note
The generated result classes carry an internal mark, and a `Failure` subclass defined by the host passes through the rebuild untouched. Generated RBS doesn't cover that case.
:::

## See also

- [Control flow](/reference/actionable/control-flow/): the verbs these codes are used with
- [Background jobs](/reference/actionable/jobs/): `honor_retry_metadata` reads the metadata
- [Testing](/reference/actionable/testing/): stubs check codes against declarations
- [RBS](/reference/actionable/rbs/): the types typed outcomes generate
