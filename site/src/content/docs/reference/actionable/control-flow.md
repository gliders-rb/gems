---
title: "Control flow"
description: "The verbs a step uses to end a run, how halting works, the rules for codes, and where a plain verb may go."
sidebar:
  order: 2
---

Steps close a run by recording an outcome through a verb. A plain verb records and lets the run continue, and a bang verb records and stops the main steps. Stopping is done with a `throw` and never with an exception (AC-I1), while a real exception from a step goes straight through `.run` (AC-I2). The verbs are all private, and `result` and `input` are the public readers.

## The verbs

| Verb | Records | Returns |
|---|---|---|
| `succeed(message = nil, **output)` | `Success` | `true` |
| `fail(code, message = nil, **errors)` | `Failure` | `false` |
| `skip(code = :skipped, message = nil, **output)` | `Skipped` | `false` |
| `fail_with(source, code: :invalid, message: nil, output: nil)` | `Failure` with `source.errors` | `false` |
| `succeed!`, `fail!`, `skip!`, `fail_with!` | the same, then `halt!` | never returns |
| `halt!` | nothing | never returns |

Whichever record comes last wins (AC-I4). If nothing was recorded, the run succeeds by itself with code `:success`. Hooks still fire after a halt (see [Hooks and history](/reference/actionable/hooks-and-history/)).

```ruby run
class Refloat < Actionable::Action
  step :strand
  step :tow

  private

  def strand = fail(:adrift)
  def tow = succeed('refloated')
end

Refloat.run.success? # => true
Refloat.run.message  # => "refloated"
```

## `succeed` and `skip`

Whatever keywords follow the message are output. With an `output` schema they survive only when they match its fields, and they override instance variables of the same name (see [Input and output](/reference/actionable/input-and-output/)). With no output schema, the keywords turn into the output Hash untouched.

```ruby run
class LogCrossing < Actionable::Action
  step :record

  private

  def record = succeed('logged', passengers: 41)
end

LogCrossing.run.output # => {passengers: 41}
```

`skip` accepts a code and defaults to `:skipped`. It isn't a failure, and `ok?` is true for it (AC-I3).

```ruby run
class RefuelTender < Actionable::Action
  step :refuel

  private

  def refuel = skip!(:tank_full, 'no fuel needed')
end

RefuelTender.run.skipped? # => true
RefuelTender.run.code     # => :tank_full
RefuelTender.run.ok?      # => true
```

## `fail`

Each keyword after the message is an error, written `field => message` or `field => [messages]`. No keyword is held back for metadata, so `fail!(:x, nil, kind: 'is not valid')` produces `errors[:kind]`. Values become Strings, element by element for an Array.

```ruby run
class DenyBoarding < Actionable::Action
  step :check

  private

  def check = fail!(:denied, 'cannot board', pass: ['is expired', 'is unsigned'])
end

result = DenyBoarding.run
result.errors.to_h # => {pass: ["is expired", "is unsigned"]}
result.message     # => "cannot board"
```

In an action, `fail` records a failure and is not `Kernel#fail`. To raise an exception, call `raise`.

### Codes

Codes have to be identifiers, matching `/\A[[:alpha:]_][[:alnum:]_]*[?!]?\z/`. Passing a sentence raises `ArgumentError` at the call. `fail 'berth unavailable'` is a `Kernel#fail` habit, and storing it as a code would bury the mistake. A String code is converted to a Symbol (AC §5.2).

```ruby run
class Phrase < Actionable::Action
  step :check

  private

  def check = fail('berth unavailable')
end

begin
  Phrase.run
rescue ArgumentError => e
  e.class # => ArgumentError
end
```

After an action declares failure codes or skip codes, it can only end with declared ones. [Declared outcomes](/reference/actionable/declared-outcomes/) has the rules.

## `fail_with`

`fail_with(source, code: :invalid, message: nil, output: nil)` takes `source.errors` from any object whose errors answer `to_h`, usually a FieldStruct, and so turns the validation of a side struct into a failure. The default code is `:invalid`, so an action that declares failures must declare that one or pass a different code.

```ruby run
class Quay < FieldStruct::Base
  required :harbour, :string
end

class Disembark < Actionable::Action
  step :check

  private

  def check = fail_with!(Quay.new, code: :bad_quay)
end

Disembark.run.errors.to_h # => {harbour: ["is required"]}
Disembark.run.code        # => :bad_quay
```

`output:` counts as output and not as an error key only if the failure code declares an output schema (or the action uses typed outcomes). In any other case `fail_with` rejects it. See [Declared outcomes](/reference/actionable/declared-outcomes/).

## `halt!` and the throw

`halt!` records nothing, stops the main steps and keeps whatever result exists. The tag it throws is `Actionable::HALT` (`:actionable_halt`), and the runner wraps steps in `Actionable.catch_halt`.

```ruby run
class DropAnchor < Actionable::Action
  step :near_shore
  step :open_sea

  private

  def near_shore
    succeed('anchored')
    halt!
  end

  def open_sea = succeed('underway')
end

DropAnchor.run.message # => "anchored"
Actionable::HALT       # => :actionable_halt
```

## Where a plain verb may go

When a plain verb has more code after it in the same method, that code still runs, and nearly always a bang was forgotten. A class's first `.run` reads its step and hook methods with Prism and raises `Actionable::DefinitionError` that names each offense, once per class (AC §5.14). The RuboCop cop `Actionable/VerbNotLast` flags the same things in your editor (see [RuboCop cop](/reference/actionable/rubocop/)).

A plain verb is fine when it is:

- the last statement of the method (a modifier `fail :x if bad?` counts as the statement)
- the last statement of a branch (`if`, `unless`, ternary, `case`, `rescue`, `ensure`) whose construct is itself last
- the right side of `&&`, `and`, `||` or `or` in last position
- returned: `return fail(:x) if bad?`, or followed directly by `return`
- the last statement of a block or loop body whose owning call is last
- followed by an `ensure` clause
- called on another receiver (`timetable.fail`, `legs.skip(1)`), which is never checked

These are offenses: the verb has more code after it, it sits in a branch whose construct is followed by more code, it is the left side of `and` or `or` (`fail(:x) and return` never reaches `return`, because `fail` returns false), it is nested inside a bigger expression (`log(fail(:x))`, `@ok = fail(:x)`), or it appears in a `begin` body that has an `else`. Bang verbs are never checked, and neither are helper methods that aren't declared steps or hooks.

```ruby
def depart
  fail(:fog_bound) if harbour.fogged?   # offense: cast_off still runs
  cast_off
end

def depart
  fail!(:fog_bound) if harbour.fogged?  # good
  cast_off
end
```

Because the check parses the method's source file, it skips methods that have none readable (`eval`, `define_method`) and files that don't parse. A subclass gets checked against its own set of methods. Passing is remembered, while failing raises again on every run until it is fixed. To switch it off for the process:

```ruby run
Actionable.verb_position_check?        # => true
Actionable.verb_position_check = false
Actionable.verb_position_check?        # => false
Actionable.verb_position_check = true
Actionable::VerbPosition.prism?        # => true
```

## See also

- [Results](/reference/actionable/results/): what each verb produces
- [Declared outcomes](/reference/actionable/declared-outcomes/): restricting the codes
- [Errors and guardrails](/reference/actionable/errors/): the checks that raise
