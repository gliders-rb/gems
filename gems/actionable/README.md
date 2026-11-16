# actionable-rb

Service objects with declared inputs, ordered steps and three strict outcomes. You subclass `Actionable::Action`, list
the steps, write each one as an ordinary method, and call `.run`. A run returns exactly one result: `Success`,
`Failure` or `Skipped`, each with a code, a message, structured errors, a typed output and a history.

```ruby
gem 'actionable-rb', '~> 2.0.0.pre1'
```

It's a pre-release, so the constraint names the pre-release version. Ruby 3.3 or newer. You `require 'actionable'` (the gem is `actionable-rb` because the short name belongs to another
project). Runtime dependencies: `field_struct`, `oj` and `prism`. Rails, RSpec and the job libraries are opt-in
requires, and the core never loads them.

## A first action

```ruby run
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

A run is a `Success`, a `Failure` or a `Skipped`, and `ok?` means "not a failure". Bad input is a failure with
structured errors, not an exception. Verbs (`fail!`, `skip!`, `succeed!`), nested actions, case steps, hooks, typed
outcomes, history, RSpec matchers, Rails transactions, background jobs and a RuboCop cop are all in the reference.

## Where to go next

- [The docs site](https://gliders-rb.github.io/) - a tutorial, how-to guides and the full reference, with every example run in CI.
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
