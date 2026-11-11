---
title: "Hooks and history"
description: "The four hook lists that run after the steps, what a hook may do to the result, and how to measure and read a run's history."
sidebar:
  order: 6
---

Hooks fire after the main steps, when the outcome is already known. Measurement keeps a record of what ran and for how long. You declare both on the class, and a subclass gets a copy at the moment it is created (AC-I6).

## Hooks

```ruby
on_success(target, **options)
on_failure(target, **options)
on_skip(target, **options)
always(target, **options)
```

A hook accepts what a step accepts: a method name or an action class, plus `if:` and `unless:`. Declaring the same hook again swaps it in place. The four lists are readable through `Action.success_hooks`, `failure_hooks`, `skip_hooks` and `always_hooks`.

The order of a run (AC §5.4):

1. The main steps run in order, all inside a single halt catch.
2. The result is whatever was recorded, or a new `Success` when nothing was.
3. Output is refreshed (see [Input and output](/reference/actionable/input-and-output/#output)).
4. One category is chosen from the result as it stands now: success picks `on_success`, skipped picks `on_skip`, everything else picks `on_failure`. That choice is final, even when a hook later changes the outcome.
5. The category's hooks run in the order declared, then the `always` hooks run inside a halt catch of their own.
6. After every hook, a result it recorded is adopted and output is refreshed once more.

```ruby run
BELL = []

class CastOff < Actionable::Action
  step :inspect_lines
  step :log_departure, if: :logged?
  on_failure :ring_bell
  always :stow_fenders

  private

  def logged? = true
  def inspect_lines = fail!(:fogbound)
  def log_departure = BELL << :log
  def ring_bell = BELL << :bell
  def stow_fenders = BELL << :fenders
end

CastOff.run.code                   # => :fogbound
BELL                               # => [:bell, :fenders]
CastOff.failure_hooks.map(&:name)  # => [:ring_bell]
CastOff.always_hooks.map(&:name)   # => [:stow_fenders]
CastOff.success_hooks.size         # => 0
CastOff.skip_hooks.size            # => 0
```

### What a hook may do

Verbs work inside hooks. A plain verb replaces the result and lets the remaining hooks run. A bang verb adopts its result and cuts off the rest of its own category, though `always` still runs and sees the new result. `halt!` leaves the result alone and ends the phase. That is why `succeed!` in an `on_failure` hook rescues the run, and `fail!(:overdue)` in an `on_success` hook turns a success into a failure (AC-B#hookverbs).

```ruby run
class Reroute < Actionable::Action
  step :depart
  on_failure :use_tender

  private

  def depart = fail!(:ebbing)
  def use_tender = succeed!('crossed by tender')
end

Reroute.run.success? # => true
Reroute.run.message  # => "crossed by tender"

class PastCurfew < Actionable::Action
  step :depart
  on_success :refuse
  on_success :unreachable

  private

  def depart = succeed
  def refuse = fail!(:overdue)
  def unreachable = raise('not reached')
end

PastCurfew.run.code # => :overdue
```

If a hook raises, the exception travels up at once and nothing after it runs, `always` hooks too (AC-I2). A hook whose guard says no is passed over. When a hook sets an instance variable named like an output field, the next refresh picks it up.

## `measure`

```ruby
measure(mode = nil, rate: nil)
```

| Mode | Records |
|---|---|
| `:none` (default) | nothing, so `history` is `[]` |
| `:all` | every run |
| `:sampled` | that share of runs; needs `rate:` from 0 to 1 inclusive |

A mode it doesn't know raises `ArgumentError` (`unknown measure mode`), and so does `:sampled` with a missing or out-of-range rate (`measure :sampled requires rate: between 0 and 1`). A rate of 1 always records, a rate of 0 never does. Called with no argument, `measure` returns the mode. The readers behind it are `measure_rate`, `measure_all?`, `measure_sampled?` and `measure_sample_hit?`. A subclass inherits a snapshot of mode and rate.

Measuring spreads downward: every run nested in a measuring run (action steps, hook actions, `run_each` items) measures as well, whatever its own `measure` says. A parent that doesn't measure passes nothing down (AC-B#cascade). The state lives per fiber, so concurrent runs stay apart, and a run in a different Fiber never shows up in the parent's history.

```ruby run
class Crossing < Actionable::Action
  measure :all

  step :load_deck
  on_success :raise_ramp

  private

  def load_deck = nil
  def raise_ramp = nil
end

Crossing.measure          # => :all
Crossing.measure_all?     # => true
Crossing.measure_rate     # => nil
Crossing.measure_sampled? # => false

class SpotCheck < Actionable::Action
  measure :sampled, rate: 0.5
end

SpotCheck.measure_rate # => 0.5
```

## History

The `history` of a measuring run is an `Actionable::History`, holding one `History::Step` for each step or hook that ran, in the order they ran. A step blocked by its guard leaves no entry. Each entry is added when its step ends, whether it halted or raised.

| Step field | Meaning |
|---|---|
| `section` | `:main` for steps; `:success`, `:failure`, `:skip` for outcome hooks; `:always` |
| `name` | the step name, or the child action class for an action step |
| `started_at` | wall-clock `Time` |
| `duration` | monotonic seconds, a Float |
| `code` | the code of the result the step recorded, or `nil` when it only set variables |
| `nested` | the child's `History` for an action step in a measuring run, else `nil` |

A history responds to `steps`, `<<(step)` (returns the history), `empty?`, `took` (total of the durations), `as_json` (an Array of step hashes) and `to_json` (via Oj, compat mode). The `as_json` keys are `section`, `name`, `started_at` (ISO 8601, six fractional digits), `duration`, `code` and `history` (the nested `as_json`, or `nil`); for an action step `name` is the class name as a String. The entry for an action step times the child run from start to finish (AC §5.11).

```ruby run
history = Crossing.run.history
history.steps.map { |s| [s.section, s.name] } # => [[:main, :load_deck], [:success, :raise_ramp]]
history.empty?                                # => false
history.took.class                            # => Float
history.as_json.first.keys # => [:section, :name, :started_at, :duration, :code, :history]
history.to_json.class                         # => String
Actionable::Action.run.history                # => []
```

## See also

- [Actions and steps](/reference/actionable/actions-and-steps/): the steps that hooks mirror
- [Control flow](/reference/actionable/control-flow/): the verbs hooks may call
- [Batches and introspection](/reference/actionable/batches-and-introspection/): `describe` lists hooks and measure mode
