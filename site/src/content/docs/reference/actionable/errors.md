---
title: "Errors and guardrails"
description: "Every exception class the gem raises and each check that raises it, with the message you will see."
sidebar:
  order: 13
---

There are only a few exception classes, but a lot of checks happen at declaration time, so a misconfigured action fails loudly the first time it loads or runs. Each message names the action (`action` when the class is anonymous) and what is wrong. One rule is different from the rest: a real exception raised inside a step, hook or guard passes straight out of `.run`, because the runner never rescues one (AC-I2).

## Exception classes

| Class | Raised when |
|---|---|
| `Actionable::Error` | base of everything this gem raises |
| `Actionable::DefinitionError` | a misconfigured action (below); also used by the adapters |
| `Actionable::Job::RetryableFailure` | `run_actionable` for a result that should be retried; has `result` |
| `Actionable::Coverage::BaselineMismatch` | the coverage report differs from its baseline |
| `ArgumentError` | a bad argument: a code that is not an identifier, an unsupported step target, a bad `measure` mode |
| `FieldStruct::UnknownAttributeError` | input with `unknown_attributes :raise` and an extra keyword |

`DefinitionError`, `RetryableFailure` and `BaselineMismatch` all inherit from `Actionable::Error`. The coverage report also raises `Actionable::Error` itself, for a missing baseline file or for a glob that matches no shard files.

```ruby run
Actionable::DefinitionError.ancestors.include?(Actionable::Error) # => true
Actionable::Error.superclass # => StandardError
FieldStruct::UnknownAttributeError.ancestors.include?(Actionable::Error) # => false
```

## Checks that raise `DefinitionError`

| Check | When | Message starts |
|---|---|---|
| missing step method | start of `.run` | `<Action> declares step(s) calling :a, :b but does not implement them` |
| undeclared failure code | at the `fail` call | `<Action> fails with :x, which it does not declare; declare it with `fails :x` (declared: ...)` |
| undeclared skip code | at the `skip` call | `<Action> skips with :x, which it does not declare; ...` |
| reserved output name | at the `output` or `fails`/`skips` block | `<Action>: output field(s) :code conflict with reserved result attributes / methods / instance variables; rename them` |
| output for a code without a schema | at the call, typed outcomes on | `<Action> fails with :x and output, but :x declares no output schema; declare one with `fails :x do ... end`` |
| own result constant | turning on `typed_outcomes` | `<Action> has its own Success, which typed outcomes would replace; rename it` |
| verb not last | first `.run` of a class | one line per offense, see below |
| `after_commit` without ActiveRecord 7.2 | at the declaration | see [Rails adapter](/reference/actionable/rails/) |

```ruby run
class RaiseGangway < Actionable::Action
  step :missing_step
end

begin
  RaiseGangway.run
rescue Actionable::DefinitionError => e
  e.message # => "RaiseGangway declares step(s) calling :missing_step but does not implement them"
end

begin
  Class.new(Actionable::Action) { output { required :code, :string } }
rescue Actionable::DefinitionError => e
  e.message.start_with?('action: output field(s) :code conflict') # => true
end
```

The missing-method check looks at steps, hooks, case-step value sources and branch targets, plus `after_commit` hooks once the Rails adapter is loaded. A method is implemented when the instance has it, public or private, and it doesn't belong to `Kernel`, `Object` or `BasicObject`, which is why `step :puts` fails. Steps that a guard would skip are checked as well, but the guard methods themselves are not (AC-B#missingmethod).

The declared-code checks fire at the call, so a code nobody reaches never raises. The gem's own codes are always allowed on failures. See [Declared outcomes](/reference/actionable/declared-outcomes/).

### The verb-position check

The first time a class runs, Prism reads every step and hook method and flags any plain verb (`fail`, `fail_with`, `skip`, `succeed`, bare or on `self`) that has code after it. Every offense in every method comes back together in a single `DefinitionError`:

```
Moor#tie_up (app/actions/moor.rb:6) calls `fail` with more code after it, which still runs: use fail! to stop here, or make it the method's last expression
(see USAGE, Control flow)
```

[Control flow](/reference/actionable/control-flow/#where-a-plain-verb-may-go) lists the tail positions that are accepted. How the check behaves (AC §5.14):

- It happens once per class. A pass is remembered and a failure is not, so the error repeats on each run until you fix it.
- Source files are read and cached by path and modification time. Methods with no readable source (`eval`, `define_method`, C), files that don't parse, and a Prism that can't load are all skipped without an error.
- For a step made with `alias_method`, the original `def` is what gets checked. If a module is prepended over a step method, it hides the class's own `def` and only the wrapper's body is read.
- `Actionable.verb_position_check = false` disables the check for the whole process. Nothing is parsed and no class is marked as checked, so switching it back on checks each class at its next run.

## Checks that raise `ArgumentError`

| Check | Message contains |
|---|---|
| a code that is not an identifier | `failure code "a b" is not an identifier; use a Symbol like :out_of_stock` |
| `step` with an unsupported target | `unsupported step target: 5` |
| unknown `measure` mode | `unknown measure mode :weird` |
| `:sampled` without a valid rate | `measure :sampled requires rate: between 0 and 1, got 3` |
| a schema block on `:invalid_input` or `:invalid_output` | `is a gem failure code and cannot declare an output schema` |
| `output:` that is not a Hash or a FieldStruct | `output: must be a Hash or a FieldStruct, got Integer` |
| an action whose `initialize` needs arguments, run with an `input` schema | Ruby's own `wrong number of arguments` |

```ruby run
begin
  Class.new(Actionable::Action) { step 5 }
rescue ArgumentError => e
  e.message # => "unsupported step target: 5"
end

begin
  Class.new(Actionable::Action) { measure :sampled, rate: 3 }
rescue ArgumentError => e
  e.message # => "measure :sampled requires rate: between 0 and 1, got 3"
end
```

:::note
`Actionable::Job.disposition`, the RSpec matcher and the stub helpers also raise `ArgumentError` for broken specs, such as naming a code the action does not declare. Those are on [Testing](/reference/actionable/testing/).
:::

## Input that raises instead of failing

With `unknown_attributes :raise` in the schema, an undeclared keyword makes `.run` raise `FieldStruct::UnknownAttributeError` and no `Failure(:invalid_input)` comes back. That is the one case where input handling raises.

```ruby run
class ReadTideTable < Actionable::Action
  input do
    required :harbour, :string
    unknown_attributes :raise
  end

  step :go

  private

  def go = succeed
end

begin
  ReadTideTable.run(harbour: 'x', extra: 1)
rescue FieldStruct::UnknownAttributeError => e
  e.class # => FieldStruct::UnknownAttributeError
end
```

## See also

- [Control flow](/reference/actionable/control-flow/): where plain verbs are allowed
- [RuboCop cop](/reference/actionable/rubocop/): the same offenses in your editor
- [Exceptions in field_struct](/reference/field-struct/exceptions/): the struct-side classes
