---
name: actionable
description: Write, debug and test Ruby service objects built with the actionable-rb gem (Actionable::Action subclasses with declared inputs, steps and success, failure or skipped results). Use when writing or changing a class that inherits Actionable::Action, reading its result, or writing specs for one.
when_to_use: The code requires 'actionable', a class inherits Actionable::Action, or the user asks for service objects with steps, typed input and output, declared failure codes, or a result object with success, failure and skipped outcomes.
---

# actionable

An action is a class that wraps one unit of business logic as an ordered list of steps. `.run` returns exactly one
result: `Success`, `Failure` or `Skipped`.

The full reference ships with the gem. Read `USAGE.md` once before writing an action (`bundle info actionable-rb` gives
the path). `docs/getting_started.md` has the task map and the error table.

## Write an action

1. Subclass `Actionable::Action`. Declare `input { ... }` (a FieldStruct body) for typed keywords, and `output { ... }`
   for the fields the result carries.
2. Declare the codes the action can end with: `fails :deck_full, 'sold out', retry: false` and `skips :already_done`.
3. List the steps with `step :name`. Each step is an instance method, public or private.
4. In a step, set instance variables named like the output fields, and use a verb to record an outcome.
5. Call `Klass.run(**params)` and check `result.success?`, `failure?` or `skipped?` (`ok?` means not a failure).

```ruby
class ClaimBunk < Actionable::Action
  input { required :seat, :string }
  output { required :ticket, :string }

  fails :taken, 'seat is taken'
  skips :already_held

  step :check
  step :issue

  private

  def check
    skip!(:already_held) if held?
    fail!(:taken) if taken?
  end

  def issue = @ticket = "T-#{input.seat}"
end
```

## The verbs

| Verb | Records |
|---|---|
| `succeed(msg = nil, **output)` | Success |
| `fail(code, msg = nil, **errors)` | Failure (keywords are errors) |
| `skip(code = :skipped, msg = nil, **output)` | Skipped |
| `fail_with(struct, code: :invalid)` | Failure with the struct's errors |
| `succeed!`, `fail!`, `skip!`, `fail_with!` | the same, then stop |
| `halt!` | nothing, stops |

Plain verbs record and continue, and the last record wins. A plain verb must be the last thing a method does, otherwise
the first `.run` raises `DefinitionError`. Use the bang form to stop.

## Common mistakes

- Treating `fail` as `raise`. Inside an action it is not `Kernel#fail`: it records a failure and keeps going. To raise, use `raise`.
- `fail(:x) if bad?` with code after it. Use `fail!`.
- A sentence as a code. Codes are identifiers, `:deck_full`.
- Failing with a code the action did not declare, once it declares any. Declare it with `fails`.
- Expecting undeclared instance variables on the result. Only `output` fields are kept.
- Output field names that clash with a Result method (`status`, `code`, `result`, `input`, `to_h`).
- Passing a Hash positionally to `.run`. Splat it.
- Forgetting the adapter require: `actionable/rails` for `transactional`, `actionable/job`, `actionable/rspec`.
- Reading metadata from `fail`'s keywords. Metadata comes from the declaration.

## Compose

- `step Child, input: %i[berth], expose: %i[line]` runs another action. A child failure fails the parent, and the
  parent must declare the code. A child skip lets the parent continue.
- `case_step :method do on 'a', :step_a; default :other end` picks a branch by value.
- `on_success`, `on_failure`, `on_skip` and `always` run after the main steps. `succeed!` in `on_failure` recovers.
- `Klass.run_each(items) { |item| { key: item } }` returns a `BatchResult`.
- `typed_outcomes` gives each action its own result classes, and `fails(:code) { required :field, :string }` gives a
  code an output schema that `fail!(:code, output: { field: 'x' })` fills.

## Serialize and inspect

`result.to_h`, `result.to_api_h(id_field: :id)`, `batch.to_api_h`, `measure :all` then `result.history.to_json`,
`Klass.describe`, `Klass.describe_text`, and `Actionable::RBS.generate(Klass)` for types.

## Jobs

`require 'actionable/job'`. `Actionable::Job.disposition(result)` answers `:ack`, `:discard` or `:retry`. Include
`Actionable::Job::Mixin` and call `run_actionable(Klass, **args)`; it raises `RetryableFailure` to retry. Metadata
decides only after `honor_retry_metadata` on the action.

## Test

`require 'actionable/rspec'`:

```ruby
expect(ClaimBunk).to perform_actionable(seat: 'A1').and_succeed
expect(ClaimBunk).to perform_actionable(seat: 'A1').and_fail(:taken)
allow_actionable_failure(ClaimBunk, code: :taken)
```

Naming a code the action does not declare raises, since that spec tests an outcome that cannot happen.
`require 'actionable/rspec/coverage'` reports declared outcomes that no spec reached, with an optional baseline file.

## Upgrade

1. Read `CHANGELOG.md` from your version to the new one.
2. Update the gem and run your suite.
3. Regenerate action signatures with `Actionable::RBS.generate` and review the diff.
