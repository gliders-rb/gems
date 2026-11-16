---
# The landing-page animation, the hero PDF and the README GIF are all generated from this file by bin/hero.
# bin/check-code-blocks runs its `ruby run` fences like a page, so every value the animation shows is asserted.
#
# Each beat is one step of the hero's stepper; `at` is when autoplay reaches it, in seconds.
# A beat with `run:` plays one call from calls.rb. Its badge and detail come from that call's `# =>` lines;
# `steps:` must match the call's asserted history. Every other claim (a mark's tag) names the line that proves it.
title: One action, three calls
message: Strings come in from a form, typed values reach your steps, and every call ends in exactly one result.
code: reserve_places.rb
calls: calls.rb
fade: 0.25
beats:
  - id: setup
    at: 0
    caption: One action. Its input is a FieldStruct and each step is a plain method.
  - id: booked
    at: 3
    run: booked
    show: [message]
    steps: [check_room, hold]
    caption: The form sent the string '4'. The steps see the integer 4.
    marks:
      - line: 'required :places, :integer'
        kind: ok
        tag: "'4' is 4"
        proof: "ReservePlaces.input.new(hut_code: 'KR12', places: '4').places   # => 4"
  - id: full
    at: 7
    run: full
    show: [code]
    steps: [check_room]
    caption: '`fail!` records the failure and stops, so `hold` never runs.'
    marks:
      - line: 'fail!(:fully_booked)'
        kind: stop
        tag: fail!
        proof: 'full.message   # => "not enough free places"'
  - id: missing
    at: 11
    run: missing
    show: [code, errors.full_messages]
    steps: []
    caption: Bad input is caught before the first step, with a message you can show.
    marks:
      - line: 'required :hut_code, :string'
        kind: stop
        tag: is required
        proof: 'missing.errors[:hut_code]   # => ["is required"]'
  - id: done
    at: 15
    caption: Three calls, one result each. Every line here runs in CI.
---

# One action, three calls

This file is the storyboard for the animation at the top of the docs home page. The front matter above is the
timeline. The Ruby below is what the animation shows, and it runs in CI like any page, so a value the animation
claims is a value Ruby returned. Sections named after a beat become that beat's page in the PDF; `measure` and
`proof` hold the checks the animation doesn't show.

## setup: One action

`ReservePlaces` holds places at a mountain hut. Its input is declared inline, which makes it a FieldStruct, and its
work is two plain methods run in order. `fails` declares the one way it can fail on purpose.

```ruby run title="reserve_places.rb"
class ReservePlaces < Actionable::Action
  input do
    required :hut_code, :string
    required :places, :integer
  end
  fails :fully_booked, 'not enough free places'

  step :check_room
  step :hold

  def check_room
    fail!(:fully_booked) if input.places > 6
  end

  def hold
    succeed("Holding #{input.places} places")
  end
end
```

## measure: Making the steps checkable

The animation marks which steps ran on each call. Measuring is off by default, so this block, which the animation
does not show, turns it on to make that checkable.

```ruby run
ReservePlaces.measure :all
```

## booked: Strings in, typed values out

A form sends every value as a string. The input struct coerces `'4'` to `4` on the way in, so `check_room` compares
integers and `hold` builds its message from one. Both steps ran, and the call ends in a success.

```ruby run title="calls.rb"
booked = ReservePlaces.run(hut_code: 'KR12', places: '4')
booked.status    # => :success
booked.message   # => "Holding 4 places"

full = ReservePlaces.run(hut_code: 'KR12', places: 9)
full.status      # => :failure
full.code        # => :fully_booked

missing = ReservePlaces.run(places: '2')
missing.status   # => :failure
missing.code     # => :invalid_input
missing.errors.full_messages   # => ["Hut code is required"]
```

## full: One failure, and the run stops

Nine places is more than the hut has free. `fail!` records the failure with its declared code and stops the run, so
`hold` never runs. The code is a plain symbol, easy to branch on, and the declared message comes with it.

## missing: Bad input never reaches a step

Without a hut code the input is invalid, so no step runs at all. The result is a failure with the code
`:invalid_input`, and it carries the input's errors as messages you can show to a person.

## proof: The claims behind the marks

These lines check the claims the animation makes beyond the three results: the coercion, the message, the error and
the steps each call ran.

```ruby run
ReservePlaces.input.new(hut_code: 'KR12', places: '4').places   # => 4
full.message   # => "not enough free places"
missing.errors[:hut_code]   # => ["is required"]
booked.history.steps.map(&:name)    # => [:check_room, :hold]
full.history.steps.map(&:name)      # => [:check_room]
missing.history                     # => []
```

## done: One result each

Three calls, three results, and each one is exactly one of success, failure or skip. Every line in this animation is
executed in CI, so a wrong value fails the build.

## links

- [Start the tutorial](https://gliders-rb.github.io/tutorial/trek-planner/)
- [Docs home](https://gliders-rb.github.io/)
- [field_struct on GitHub](https://github.com/gliders-rb/gems/tree/main/gems/field_struct)
- [actionable on GitHub](https://github.com/gliders-rb/gems/tree/main/gems/actionable)
