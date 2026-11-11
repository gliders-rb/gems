---
title: "How to call one action from another"
description: "Use an action as a step, pass values in, take outputs back, and let a child failure stop the parent."
sidebar:
  label: "Compose actions"
  order: 8
---

`ClearDeparture` has to weigh the cargo before a ferry leaves, and `WeighCargo` already does that as an action of its own.

## 1. Write the child

The child is a normal action. It has its own input and its own output, and knows nothing about whoever calls it.

```ruby run
class WeighCargo < Actionable::Action
  input { required :manifest, :string }
  output { required :bay_label, :string }

  fails :unmanifested

  step :weigh

  private

  def weigh
    fail!(:unmanifested, 'no cargo list') unless input.manifest.end_with?('.csv', '.json')
    @bay_label = "#{input.manifest}#deck2"
  end
end
```

## 2. Use it as a step

Hand the class to `step`. With `input:` you list the parent's instance variables to send, one keyword each, and `expose:` limits what comes back onto the parent after the child succeeds.

```ruby run
class ClearDeparture < Actionable::Action
  input do
    required :vessel, :string
    required :manifest, :string
  end

  output { required :bay_label, :string }

  fails :unmanifested

  step :prepare
  step WeighCargo, input: %i[manifest], expose: %i[bay_label]
  step :depart

  private

  def prepare = @manifest = input.manifest

  def depart = succeed("cleared #{input.vessel}")
end

result = ClearDeparture.run(vessel: 'Gannet', manifest: 'tuesday.csv')
result.message     # => "cleared Gannet"
result.bay_label   # => "tuesday.csv#deck2"
ClearDeparture.steps.map(&:kind)   # => [:method, :action, :method]
```

Values cross over as instance variables, which is why `prepare` sets `@manifest`. An unset variable goes out as `nil`, and a field the child leaves unset never overwrites one the parent already holds.

## 3. Let a child failure stop the parent

When the child fails, the parent fails the same way: same code, message, errors and metadata, and none of the later steps run. The parent must declare every code its children can fail with. If it doesn't, the run raises `DefinitionError`.

```ruby run
failed = ClearDeparture.run(vessel: 'Gannet', manifest: 'tuesday.txt')
failed.failure?   # => true
failed.code       # => :unmanifested
failed.message    # => "no cargo list"
```

## 4. Remember that a child skip does not stop anything

The parent does not see a skip as an outcome. It carries on as though the child had succeeded. To stop on a skip, check for it in the step that follows.

## 5. Look at what ran

History is off until you ask. `measure :all` records each step that ran, and when the parent measures, the children measure too.

```ruby run
class Logged < ClearDeparture
  measure :all
end

history = Logged.run(vessel: 'Gannet', manifest: 'tuesday.csv').history
history.steps.map(&:name)             # => [:prepare, WeighCargo, :depart]
history.steps[1].nested.steps.map(&:name)   # => [:weigh]
```

## See also

- [Actions and steps](/reference/actionable/actions-and-steps/#nested-actions)
- [Hooks and history](/reference/actionable/hooks-and-history/)
- [Composing actions](/tutorial/composing-actions/)
