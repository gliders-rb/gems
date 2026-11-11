# actionable-rb

Service objects with declared inputs, ordered steps and three strict outcomes. You subclass `Actionable::Action`, list
the steps, write each one as an ordinary method, and call `.run`. A run returns exactly one result: `Success`,
`Failure` or `Skipped`, each with a code, a message, structured errors, a typed output and a history.

```ruby
gem 'actionable-rb'
```

Ruby 3.3 or newer. You `require 'actionable'` (the gem is `actionable-rb` because the short name belongs to another
project). Runtime dependencies: `field_struct`, `oj` and `prism`. Rails, RSpec and the job libraries are opt-in
requires, and the core never loads them.

## A first action

<!-- doctest -->
```ruby
require 'actionable'

class BookCrossing < Actionable::Action
  input do
    required :callsign, :string
    required :quantity, :integer, in: 1..10
  end

  output do
    required :fare_pence, :integer
  end

  fails :fully_booked, 'not enough stock', retry: false

  step :check_ballast
  step :toll

  private

  def check_ballast
    fail!(:fully_booked) if input.quantity > 5
  end

  def toll
    @fare_pence = input.quantity * 1_250
  end
end

result = BookCrossing.run(callsign: 'ana@example.com', quantity: '2')
result.success?       # => true
result.fare_pence    # => 2500
result.code           # => :success

fully_booked = BookCrossing.run(callsign: 'ana@example.com', quantity: 7)
fully_booked.failure?     # => true
fully_booked.code         # => :fully_booked
fully_booked.message      # => "not enough stock"
fully_booked.metadata     # => {retry: false}
```

Steps are instance methods, so they can be private. They set instance variables, and only the fields declared in
`output` reach the result. Nothing is captured by accident.

## One result, three outcomes

| Outcome | Meaning | `ok?` |
|---|---|---|
| `Success` | the action did what it was for | true |
| `Skipped` | there was nothing to do - not an error, not a success | true |
| `Failure` | it could not do it | false |

`success?`, `skipped?` and `failure?` are mutually exclusive, and `ok?` means "not a failure". The `code` says why.

<!-- doctest -->
```ruby
require 'actionable'

class Salute < Actionable::Action
  skips :already_saluted, 'nothing to send'

  step :check

  private

  def check
    skip!(:already_saluted)
  end
end

result = Salute.run
result.skipped?   # => true
result.ok?        # => true
result.status     # => :skipped
```

## Bad input is a failure, not an exception

With an `input` block the keywords of `.run` are coerced and validated by FieldStruct before any step runs. An invalid
input ends the run as `Failure(:invalid_input)` with the errors attached.

<!-- doctest -->
```ruby
require 'actionable'

class Enlist < Actionable::Action
  input { required :callsign, :email }
  step :save

  private

  def save = succeed('subscribed')
end

bad = Enlist.run(callsign: 'adrift')
bad.code             # => :invalid_input
bad.errors.to_h.keys # => [:callsign]
Enlist.run(callsign: 'ana@example.com').message   # => "subscribed"
```

## Verbs

| Verb | Records | Stops the run |
|---|---|---|
| `succeed(msg = nil, **output)` | `Success` | no |
| `fail(code, msg = nil, **errors)` | `Failure` | no |
| `skip(code = :skipped, msg = nil, **output)` | `Skipped` | no |
| `succeed!`, `fail!`, `skip!` | the same | yes |
| `fail_with(source, code: :invalid)` | `Failure` with `source.errors` | no (`fail_with!` stops) |
| `halt!` | nothing | yes |

The last record wins. A plain verb has to be the last thing a method does, otherwise the code after it still runs. The
first `.run` of a class checks this and raises with the line number, and a RuboCop cop (`Actionable/VerbNotLast`) says
it earlier. Inside an action `fail` records a failure, it is not `Kernel#fail`: to raise an exception, use `raise`.

## Composition

Steps can be a method, another action, or a `case_step` that picks a branch by value. Hooks (`on_success`,
`on_failure`, `on_skip`, `always`) run after the main steps. A child action's failure becomes the parent's failure.

<!-- doctest -->
```ruby
require 'actionable'

class Claim < Actionable::Action
  input { required :berth, :string }
  output { optional :reservation, :string }

  fails :deck_full

  step :reserve

  private

  def reserve
    fail!(:deck_full) if input.berth == 'gone'
    @reservation = "R-#{input.berth}"
  end
end

class Embark < Actionable::Action
  output { optional :reservation, :string }

  fails :deck_full

  def initialize(berth: nil)
    super()
    @berth = berth
  end

  step Claim, input: %i[berth], expose: %i[reservation]
  on_success :log

  private

  def log = @log = 'checked out'
end

Embark.run(berth: 'book').reservation      # => "R-book"
Embark.run(berth: 'gone').code             # => :deck_full
```

## What else is in the box

- `measure :all` keeps a `History` of every step and hook with timings, and `result.history.to_json` serializes it.
- `typed_outcomes` gives each action its own `Success`, `Failure` and `Skipped` classes and per-code output schemas.
- `Action.describe` and `describe_text` summarize an action. `Actionable::RBS.generate(Klass)` writes its RBS.
- `actionable/rspec` adds the `perform_actionable` matcher and result stubs. `actionable/rspec/coverage` reports which
  declared outcomes no spec reached.
- `actionable/rails` adds `transactional` and `after_commit`, and `actionable/job` maps a result to ack, discard or
  retry for a background job.
- `actionable/rubocop` is the `Actionable/VerbNotLast` cop.

## Where to go next

- [USAGE.md](USAGE.md) - the reference, example first. Every public method is named there.
- [docs/getting_started.md](docs/getting_started.md) - a task-to-API map and what each error means.
- [AGENTS.md](AGENTS.md) and [skills/actionable/SKILL.md](skills/actionable/SKILL.md) - the same guidance for coding agents.
- [CHANGELOG.md](CHANGELOG.md)

## Development

```
bundle exec rake                 # specs and RuboCop
bundle exec rake release:check   # adds doctests, signature checks, the docs check and the YARD build
bundle exec rake bench           # indicative timings
```

MIT licensed.
