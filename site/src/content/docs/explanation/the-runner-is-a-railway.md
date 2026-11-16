---
title: "The runner is a railway"
description: "Why every run goes through one runner that leaves the main track at the first outcome, and which hooks run for each way off it."
sidebar:
  order: 6
---

A car pulls up at the ferry terminal to check in for a sailing. We look up the sailing, make sure the car deck has room and give the car a lane. Written as plain Ruby, it tends to come out like this:

```ruby
def check_in_car(plate, sailing)
  return { status: :skipped } if CHECKED_IN.include?(plate)

  spaces = SPACES.fetch(sailing) { return offer_next_sailing(plate, :no_sailing) }
  return offer_next_sailing(plate, :deck_full) if spaces.zero?

  lane = spaces
  print_lane_ticket(plate, lane)
  { status: :success, lane: lane }
rescue IOError => e
  { status: :failed, reason: e.message }
ensure
  log_arrival(plate)
end
```

Every `return` is a way out, and each one has to remember its own cleanup. The work for a good outcome (the ticket) sits in the middle of the main path, and the work for a bad one is repeated before each exit. Add a fourth check and you have one more exit to get right.

## The same check-in as steps

```ruby run
SPACES = { 'dawn' => 2, 'noon' => 0, 'dusk' => :offline }.freeze
CHECKED_IN = ['RT-07'].freeze
STAFF = ['CREW-1'].freeze
LOG = []

class CheckInCar < Actionable::Action
  input do
    required :plate, :string
    required :sailing, :string
  end

  output { required :lane, :integer }

  fails :no_sailing, 'no such sailing today'
  fails :deck_full, 'the car deck is full'
  skips :already_checked_in

  step :check_ticket
  step :find_sailing
  step :check_deck
  step :assign_lane

  on_success :print_lane_ticket
  on_failure :offer_next_sailing
  on_skip :wave_through
  always :log_arrival

  private

  def check_ticket
    skip!(:already_checked_in) if CHECKED_IN.include?(input.plate)
    return unless STAFF.include?(input.plate)

    @lane = 0
    succeed!
  end

  def find_sailing
    fail!(:no_sailing) unless SPACES.key?(input.sailing)
  end

  def check_deck
    raise IOError, 'deck sensor offline' if SPACES[input.sailing] == :offline

    fail!(:deck_full) if SPACES[input.sailing].zero?
  end

  def assign_lane = @lane = SPACES[input.sailing]

  def print_lane_ticket = LOG << :print_lane_ticket
  def offer_next_sailing = LOG << :offer_next_sailing
  def wave_through = LOG << :wave_through
  def log_arrival = LOG << :log_arrival
end

def check_in(**args)
  LOG.clear
  [CheckInCar.run(**args), LOG.dup]
end

result, hooks = check_in(plate: 'KX-41', sailing: 'dawn')
result.lane   # => 2
hooks         # => [:print_lane_ticket, :log_arrival]
```

The steps are the main track and they run in order. The hooks are not steps: they run once, after the main track ends, and which ones run depends on how it ended. `on_success`, `on_failure` and `on_skip` each belong to one outcome, and `always` runs after whichever of them was picked.

This shape has a name. It comes from railway-oriented programming, a way of describing error handling that grew up in the functional programming world: each step either passes the train along the main track or switches it to a side track that runs past everything that is left. A step never has to ask whether an earlier one went wrong, since if it had, this step would not be running.

## Ways off the main track

A declared failure with `fail!` stops the main track, so `assign_lane` never runs. Only the failure hooks and `always` follow.

```ruby run
result, hooks = check_in(plate: 'KX-41', sailing: 'noon')
result.code   # => :deck_full
hooks         # => [:offer_next_sailing, :log_arrival]
```

A skip with `skip!` stops it too, and takes the skip track instead. Nothing went wrong, so `on_failure` stays quiet.

```ruby run
result, hooks = check_in(plate: 'RT-07', sailing: 'dawn')
result.skipped?   # => true
hooks             # => [:wave_through, :log_arrival]
```

`succeed!` records a success and stops the main track, so a staff car gets lane 0 and skips the rest of the checks. The bare `halt!` stops the track without recording anything: the run keeps what was recorded so far, and with nothing recorded it raises `Actionable::DefinitionError` ("record an outcome first, or use skip!"). Stopping with nothing to report is a skip, so say so with `skip!`.

```ruby run
result, hooks = check_in(plate: 'CREW-1', sailing: 'noon')
result.success?   # => true
result.lane       # => 0
hooks             # => [:print_lane_ticket, :log_arrival]
```

Invalid input never boards at all. The input is checked before the runner starts, so no step and no hook runs, `always` included.

```ruby run
result, hooks = check_in(sailing: 'dawn')
result.code          # => :invalid_input
result.errors.to_h   # => {plate: ["is required"]}
hooks                # => []
```

A real exception is not a track. It leaves `.run` as it was raised, and the hooks that had not run yet never run, `always` included.

```ruby run
LOG.clear
begin
  CheckInCar.run(plate: 'KX-41', sailing: 'dusk')
rescue IOError => e
  e.message   # => "deck sensor offline"
end
LOG           # => []
```

## What differs from the textbook railway

The textbook version has two tracks. Ours has three, because a skip is its own outcome (see [Success, failure, skip](/explanation/three-outcomes/)). The plain verbs, `fail` and `skip` without the bang, record an outcome and stay on the main track, so a later step can still change it. Only the bang forms switch tracks.

A hook can switch tracks too. An `on_failure` hook calling `succeed!` turns the run into a success, but the runner picks the hook phase only once, so no `on_success` hook runs after it (see [Hooks and history](/reference/actionable/hooks-and-history/)).

The cost shows up when you compare `always` with the first example's `ensure`. An exception skips every hook, so `always` is not cleanup. When something must happen on every exit, exceptions included, write an `ensure` in your own code around `.run`.

## See also

- [Control flow](/reference/actionable/control-flow/)
- [Hooks and history](/reference/actionable/hooks-and-history/)
- [Success, failure, skip](/explanation/three-outcomes/)
