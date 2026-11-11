---
title: "Actions and steps"
description: "How to declare an action, run it, and build it from method steps, case steps and nested actions."
sidebar:
  order: 1
---

An action subclasses `Actionable::Action`, and each of its steps is an instance method (public or private). Every `.run` creates a new instance, so nothing carries over between calls. Here we cover how to declare steps and how to run them. The verbs that end a run live on [Control flow](/reference/actionable/control-flow/), and the object `.run` hands back is on [Results](/reference/actionable/results/).

## `.run`

```ruby
Action.run(*args, **kwargs) # => Result
```

When the class has an `input` block, `.run(**kwargs)` builds the input struct and the steps read it as `input` (see [Input and output](/reference/actionable/input-and-output/)). Without the block the action is free-form, so `.run` forwards `*args` and `**kwargs` to `new` and the default constructor discards them. You always get exactly one result back, and a run that records no outcome succeeds on its own (AC §5.4).

```ruby run
class StampPass < Actionable::Action
  input { required :pass_no, :string }
  output { required :stamped_no, :string }

  step :stamp

  private

  def stamp
    @stamped_no = input.pass_no.delete('/')
  end
end

StampPass.run(pass_no: 'BP/204/7').stamped_no # => "BP2047"
StampPass.steps.map(&:name)                   # => [:stamp]
StampPass.run.code                            # => :invalid_input
```

A free-form action that wants its own arguments overrides `initialize` and calls `super()`:

```ruby run
class Hail < Actionable::Action
  def initialize(vessel)
    super()
    @vessel = vessel
  end

  step :hail

  private

  def hail = succeed("ahoy #{@vessel}")
end

Hail.run('Gannet').message        # => "ahoy Gannet"
Actionable::Action.run.success?   # => true
```

:::caution
When an action has an `input` block, the gem calls `new` with no arguments and assigns the input afterwards. An `initialize` override has to work with zero required arguments and call `super`, or `.run` raises Ruby's `ArgumentError` (AC §5.6).
:::

## `step`

```ruby
step(target, **options)
```

| Target | Kind | Meaning |
|---|---|---|
| Symbol or String | `:method` | call the instance method of that name |
| an `Action` subclass | `:action` | run that action as a step (see [nested actions](#nested-actions)) |

| Option | Applies to | Meaning |
|---|---|---|
| `if:` | all steps | run only when the guard is truthy |
| `unless:` | all steps | skip when the guard is truthy |
| `input:` | action steps | names of instance variables to pass to the child |
| `expose:` | action steps | narrow the child's output fields copied back |

Steps execute in the order declared, and `step 'name'` is the same step as `step :name`. Any other kind of target (`step 5`) raises `ArgumentError` with `unsupported step target`. A step object answers `name`, `kind` and `options`, and two steps are equal when their class and name match. `Action.steps` lists them in order (AC §5.3).

### Guards

`if:` and `unless:` accept a method name or a callable that gets the instance. If both are present, whichever one asks to skip wins. A step that is skipped this way never runs and leaves no entry in the history. Guard methods can be private, but the missing-method check ignores them, so a misspelled guard raises `NoMethodError` only when it is evaluated, partway through a run (AC-B#guards).

```ruby run
class ClearDeparture < Actionable::Action
  input { required :vessel, :string }

  step :inspect_hull
  step :scrub_ballast, if: :ballast_dirty?
  step :ring_bell, unless: ->(action) { action.input.vessel.length < 5 }
  step :cast_off

  def initialize
    super
    @trail = []
  end

  private

  def ballast_dirty? = false
  def inspect_hull = @trail << :inspect_hull
  def scrub_ballast = @trail << :scrub_ballast
  def ring_bell = @trail << :ring_bell
  def cast_off = succeed(@trail.join(','))
end

ClearDeparture.run(vessel: 'Heron II').message  # => "inspect_hull,ring_bell"
ClearDeparture.run(vessel: 'Tern').message      # => "inspect_hull"
ClearDeparture.steps.to_a[1].options            # => {if: :ballast_dirty?}
```

### Redeclaration and inheritance

Declare a step a second time (same kind, same name) and its options are replaced where it stands, so it keeps its first position. `step :x` and `case_step :x` count as different steps, and so do `on_success :x` and `always :x`, since every hook list is separate.

A subclass takes a copy of the steps, hooks, schemas, declarations, `measure` and `typed_outcomes` at creation time (AC-I6). The parent can change afterwards without affecting it, and redeclaring a step in the subclass touches the subclass only. An inherited step can't be removed, so switch it off with `if:` or `unless:`.

```ruby run
class BaseDeparture < Actionable::Action
  step :load_deck
  step :sound_horn

  private

  def load_deck = nil
  def sound_horn = nil
end

class SilentDeparture < BaseDeparture
  step :sound_horn, unless: ->(_action) { true }
end

BaseDeparture.steps.map(&:options)  # => [{}, {}]
SilentDeparture.steps.map(&:name)   # => [:load_deck, :sound_horn]
SilentDeparture.steps.to_a.last.options.keys # => [:unless]
SilentDeparture.steps.equal?(BaseDeparture.steps) # => false
```

## `case_step`

```ruby
case_step(value_method, **options) { on(match, target, **opts); default(target, **opts) }
```

A case step calls the named method (private works), then runs the first branch whose match accepts the returned value. The target is either a method name or an action class, and `default` takes whatever is left.

| Match | Accepts |
|---|---|
| a value | values equal to it (`==`) |
| an Array | any value the Array includes |
| a Regexp | values whose `to_s` matches |

`Actionable::ValueMatch.matches?(branch_value, value)` is the matcher everything shares. A Range never matches one of its members since it is compared with `==` only, so spell it `(400..499).to_a` rather than `400..499`. A `nil` branch matches `nil` (AC-B#valuematch).

```ruby run
class AssignQuay < Actionable::Action
  input { required :cargo, :string }

  case_step :cargo do
    on 'foot', :use_gangway
    on %w[car van], :use_ramp
    on(/\Acrane/, :use_hoist)
    default :use_tender
  end

  private

  def cargo = input.cargo
  def use_gangway = succeed('gangway')
  def use_ramp = succeed('ramp')
  def use_hoist = succeed('hoist')
  def use_tender = succeed('tender')
end

AssignQuay.run(cargo: 'van').message        # => "ramp"
AssignQuay.run(cargo: 'crane-lift').message # => "hoist"
AssignQuay.run(cargo: 'livestock').message  # => "tender"
AssignQuay.steps.first.kind                 # => :case
Actionable::ValueMatch.matches?((400..499), 450) # => false
Actionable::ValueMatch.matches?((400..499).to_a, 450) # => true
```

When nothing matches and there is no `default`, the step does nothing and no error is raised. Branches accept `if:` and `unless:` just like steps do. The value alone picks the branch, and only then does its guard decide whether the target runs. If the matched branch's guard opts out, nothing happens and a later branch is not tried. `case_step` is built on `Steps::Case.define(value_source, **options)`, and the resulting step answers `branches` (`[match_value, step]` pairs) and `default_step`.

## Nested actions

```ruby
step ChildAction, input: %i[berth], expose: %i[pass]
```

A nested action amounts to `Child.run(berth: @berth)`. For each name listed in `input:`, the parent hands over its instance variable of that name as a keyword, and an unset variable goes in as `nil`. After a success or a skip, the fields the child really set come back to the parent as instance variables, limited by `expose:`. A field the child never set can't overwrite what the parent holds (AC-B#nestedabsorb).

```ruby run
class HoldBerth < Actionable::Action
  input { required :berth, :string }
  output { required :held, :boolean }

  step :hold

  private

  def hold = @held = true
end

class IssueBoarding < Actionable::Action
  step HoldBerth, input: %i[berth], expose: %i[held]
  step :finish

  def initialize
    super
    @berth = 'D2-17'
    @deck = 'upper'
  end

  private

  def finish = succeed("held=#{@held} deck=#{@deck}")
end

IssueBoarding.run.message # => "held=true deck=upper"
IssueBoarding.steps.first.kind # => :action
```

When the child fails, the parent fails too and stops. It takes over the child's code, message, errors and metadata directly, never passing through its own `fail`. A parent that declares any failure code has to declare every non-gem code its children can fail with, otherwise `DefinitionError` is raised, while the gem's own `:invalid_input` and `:invalid_output` pass through freely (AC §5.8, AC-B#nesteddeclare). A child's skip doesn't count as an outcome for the parent, which carries on as it would after a success. If the parent measures, the child's history is attached to the matching step record (see [Hooks and history](/reference/actionable/hooks-and-history/)).

## Checks before and during a run

`.run` goes through these stages in order: build and validate the input (invalid input returns its failure right there), instantiate, check for missing methods, check verb positions on the first run, then run the steps (AC-B#runorder).

- **Missing methods.** Each step, hook and case-branch method has to exist on the instance, public or private, and can't come from `Kernel`, `Object` or `BasicObject`, so `step :puts` fails. The error is a `DefinitionError`: `<Action> declares step(s) calling :a, :b but does not implement them`. A step whose guard would skip it is still checked.
- **Verb position.** The first run of a class raises `DefinitionError` when a plain verb has more code after it. [Errors and guardrails](/reference/actionable/errors/) has the details.

## See also

- [Control flow](/reference/actionable/control-flow/): the verbs a step calls
- [Hooks and history](/reference/actionable/hooks-and-history/): what runs after the steps
- [Declared outcomes](/reference/actionable/declared-outcomes/): codes a nested child may fail with
