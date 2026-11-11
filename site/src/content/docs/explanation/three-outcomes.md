---
title: "Success, failure, skip"
description: "Why a skip is its own outcome, why recording an outcome is not stopping, and why halting is a throw and not an exception."
sidebar:
  order: 5
---

A sync action pulls new sailings from a timetable feed. On a day with nothing new, what did it do?

```ruby run
class SyncTimetable < Actionable::Action
  input { required :new_sailings, :integer }

  step :sync

  private

  def sync
    skip!(:up_to_date, 'nothing new') if input.new_sailings.zero?
    succeed("synced #{input.new_sailings}")
  end
end

quiet = SyncTimetable.run(new_sailings: 0)
quiet.skipped?   # => true
quiet.failure?   # => false
quiet.success?   # => false
quiet.ok?        # => true
```

Nothing failed, so nobody should be paged. Nothing succeeded either, since no work happened and a metric of synced runs should not count it. That is a skip, meaning there was nothing to do. Every result is exactly one of the three, never two (AC-I3).

## Why a third outcome

Most code has a boolean here: it worked or it did not. The trouble sits in between. Turn a skip into a success and a dashboard says "synced" for runs that synced nothing. Turn it into a failure and alerting wakes someone on a quiet night, while a job queue keeps retrying something that will never change.

The price of keeping `Skipped` strict is one more branch for every caller. We think it pays off, because once the information has been collapsed it is hard to recover. `ok?` exists for callers that don't care which of the two good outcomes they got.

A child's skip is also not an outcome for its parent, which carries on as if the child had succeeded (see [Compose actions](/how-to/compose-actions/)). We looked at propagating it and passed for now, because that would change what every existing composed action means.

## Recording is not stopping

`fail` and `succeed` note the outcome and keep going. Only the bang forms, `fail!` and `succeed!`, also stop (AC-I4), and the last record wins.

```ruby run
class Regroup < Actionable::Action
  step :first
  step :second

  private

  def first = fail(:adrift)
  def second = succeed('regrouped')
end

Regroup.run.success?   # => true
```

This is a trade. An earlier design had the plain `fail` stop quietly through a hidden flag, which left the bang forms redundant and the rules uneven. When plain verbs only record, the rule is clear and a later step can recover from an earlier failure. The cost is a trap: `fail(:x) if bad?` followed by more code keeps running that code. So the gem checks for it on the first run and ships a RuboCop cop (see [Lint with the RuboCop cop](/how-to/catch-misplaced-verbs/)).

## Halting is a throw

A bang verb stops with a `throw`, which the runner catches (AC-I1). No exception is ever raised for control flow, and the payoff is the reverse direction: a real exception can't be mistaken for a deliberate stop.

```ruby run
class Stranded < Actionable::Action
  step :go

  private

  def go = raise('the radio is dead')
end

begin
  Stranded.run
rescue RuntimeError => e
  e.message   # => "the radio is dead"
end
```

A real exception goes through `.run` untouched (AC-I2). It is not a failure, since a failure is something the action expected and gave a name. An exception is a bug or an outage, and your error tracker should see it. Control flow built on exceptions tends to swallow exactly those, usually under a broad `rescue`.

The cost is that no cleanup hook runs when an exception escapes. Hooks belong to outcomes, and an exception is not one. For cleanup on every exit, write an `ensure` in your own code.

## See also

- [Control flow](/reference/actionable/control-flow/)
- [Results](/reference/actionable/results/)
- [Declared failures and result codes](/explanation/declared-outcomes/)
