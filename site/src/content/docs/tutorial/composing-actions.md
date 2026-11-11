---
title: "Composing actions"
description: "Split the trek plan into small actions, use one as a step of another, undo work when a later step fails, and read the history."
sidebar:
  label: "5. Composing actions"
  order: 6
---

`ReservePlaces` is about to grow. A trek also needs a shuttle to the trailhead and, now and then, a porter for the heavy packs. In this chapter we split the work into small actions and let a `PlanTrek` action run them in order.

## Where we left off

We had one action that checked and took free places. Here that part stands alone, next to a table of shuttle times and a table of porter loads.

```ruby run title="small_actions.rb"
FREE = { 'KR12' => 3 }
SHUTTLES = { 'north' => 35, 'east' => 80 }
PORTERS = { 'LIGHT' => 8, 'FULL' => 20 }

class TakePlaces < Actionable::Action
  input do
    required :hut_code, :string
    required :places, :integer
  end

  output do
    required :remaining, :integer
  end

  fails :fully_booked, 'not enough places free'

  step :check
  step :take

  private

  def check
    fail!(:fully_booked) if FREE.fetch(input.hut_code, 0) < input.places
  end

  def take
    FREE[input.hut_code] -= input.places
    @remaining = FREE[input.hut_code]
  end
end

class ChooseTrailhead < Actionable::Action
  input { required :valley, :string }
  output { required :shuttle_minutes, :integer }

  fails :no_shuttle, 'no shuttle serves that valley'

  step :pick

  private

  def pick
    minutes = SHUTTLES[input.valley]
    fail!(:no_shuttle) unless minutes
    @shuttle_minutes = minutes
  end
end

class AddPorter < Actionable::Action
  input { optional :porter_code, :string }
  output { optional :porter_kg, :integer }

  skips :no_porter

  step :assign

  private

  def assign
    skip!(:no_porter) if input.porter_code.nil?
    @porter_kg = PORTERS.fetch(input.porter_code, 0)
  end
end
```

Each one runs alone, and each is easy to test.

```ruby run
ChooseTrailhead.run(valley: 'east').shuttle_minutes   # => 80
ChooseTrailhead.run(valley: 'west').code              # => :no_shuttle
AddPorter.run.skipped?                                # => true
```

## An action as a step

A `step` can name an action class instead of a method. The parent passes values by naming instance variables with `input:`, and takes outputs back as instance variables, narrowed with `expose:`.

```ruby run title="plan_trek.rb"
class PlanTrek < Actionable::Action
  input do
    required :hut_code, :string
    required :places, :integer
    required :valley, :string
    optional :porter, :string
  end

  output do
    required :remaining, :integer
    required :shuttle_minutes, :integer
    optional :porter_kg, :integer
  end

  fails :fully_booked, 'not enough places free'
  fails :no_shuttle, 'no shuttle serves that valley'

  step :prepare
  step TakePlaces, input: %i[hut_code places], expose: %i[remaining]
  step ChooseTrailhead, input: %i[valley], expose: %i[shuttle_minutes]
  step AddPorter, input: %i[porter_code], expose: %i[porter_kg]

  private

  def prepare
    @hut_code = input.hut_code
    @places = input.places
    @valley = input.valley
    @porter_code = input.porter
  end
end
```

The `prepare` step copies the typed input into instance variables, since that's what child steps read. Let's run it.

```ruby run
done = PlanTrek.run(hut_code: 'KR12', places: 1, valley: 'east', porter: 'LIGHT')

done.success?           # => true
done.remaining          # => 2
done.shuttle_minutes    # => 80
done.porter_kg          # => 8
```

## A child skip does not stop the parent

With no porter requested, `AddPorter` skips. The parent carries on, as it would after a success.

```ruby run
plain = PlanTrek.run(hut_code: 'KR12', places: 1, valley: 'north')

plain.success?          # => true
plain.porter_kg         # => nil
plain.shuttle_minutes   # => 35
FREE['KR12']            # => 1
```

A skip means "nothing to do here". The parent doesn't have to handle it.

## A child failure becomes the parent's

Asking for more places than are free makes `TakePlaces` fail, and `PlanTrek` fails with the same code.

```ruby run
full = PlanTrek.run(hut_code: 'KR12', places: 5, valley: 'north')

full.failure?    # => true
full.code        # => :fully_booked
full.message     # => "not enough places free"
```

Because `PlanTrek` declares failures, it has to declare every code its children can fail with. Leave out `:no_shuttle` and the first run raises `Actionable::DefinitionError`, naming the code.

## Undo with on_failure

Here is a real problem. When the valley has no shuttle, `TakePlaces` already took a place, and nobody can reach the hut. An `on_failure` hook runs after a failed run, so we give the place back.

```ruby run
class PlanTrek
  on_failure :release_places

  private

  def release_places
    FREE[@hut_code] += @places if @remaining
  end
end

before = FREE['KR12']
stuck = PlanTrek.run(hut_code: 'KR12', places: 1, valley: 'west')

stuck.code                  # => :no_shuttle
FREE['KR12'] == before      # => true
```

The hook ran only because the run failed, and `@remaining` is set only when `TakePlaces` got far enough to succeed. After a `:fully_booked` failure nothing was taken, so there is nothing to give back.

## See what ran

An action that measures keeps a history of every step.

```ruby run
class PlanTrek
  measure :all
end

traced = PlanTrek.run(hut_code: 'KR12', places: 1, valley: 'north')
traced.history.steps.size                           # => 4
traced.history.steps.map(&:section).uniq            # => [:main]
traced.history.took.class   # => Float
```

The four entries are `prepare` and the three child actions, and no `:failure` entry shows up because nothing failed. Each entry names the section (`:main` for steps, `:failure` for the undo hook), the step and how long it took. Measuring is off by default, so a normal run pays nothing.

## What you built

Three small actions and a `PlanTrek` that composes them. A child skip let the parent go on, a child failure became the parent's, an `on_failure` hook returned the place, and `history` showed what ran.

Next we take the trek planner into an app.

## See also

- [Into an app](/tutorial/into-an-app/): the next chapter
- [Compose actions](/how-to/compose-actions/)
- [Hooks and history](/reference/actionable/hooks-and-history/)
- [Actions and steps](/reference/actionable/actions-and-steps/#nested-actions)
