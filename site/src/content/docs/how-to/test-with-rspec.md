---
title: "How to test structs and actions with RSpec"
description: "Assert an action's outcome in one line, build results without stubbing, and replace a collaborator action."
sidebar:
  label: "Test with RSpec"
  order: 11
---

Say you have a `Voyage` struct and a `LogCrossing` action, and you want specs that read like the outcome they check.

`actionable/rspec` needs RSpec, and the site's bundle has none. So most of this page is plain code. The matcher and the result builders are tried on a small object that extends the same modules.

## 1. Load the helpers

```ruby
# spec/spec_helper.rb
require 'actionable/rspec'
```

If `RSpec` is defined, this pulls the matcher and the stub helpers into every example group. Coverage is a separate require, `actionable/rspec/coverage`.

## 2. Test a struct

A struct spec is ordinary RSpec. Check validity and the messages, and leave `inspect` alone.

```ruby
RSpec.describe Voyage do
  it 'needs a route' do
    voyage = described_class.new(route: '')

    expect(voyage).not_to be_valid
    expect(voyage.errors[:route]).to eq(['is required'])
  end

  it 'reads a date from a string' do
    expect(described_class.new(route: 'Quay-Isle', departs_on: '2026-07-03').departs_on).to eq(Date.new(2026, 7, 3))
  end
end
```

## 3. Test the outcome in one line

`perform_actionable` calls `.run` on the class and inspects the result. On its own it expects success, and the chains name every other outcome.

```ruby
RSpec.describe LogCrossing do
  it { is_expected.to perform_actionable(route: 'Quay-Isle') }
  it { is_expected.to perform_actionable(route: 'Quay-Isle', logged: true).and_skip(:already_logged) }
  it { is_expected.to perform_actionable.and_fail(:missing_route, /needs a route/) }
end
```

If the action declares its codes, asking for one it doesn't declare raises `ArgumentError` inside the spec. That is on purpose, because such a spec would assert an outcome the action can never produce. To show it, we ran the matcher outside RSpec:

```ruby run
require 'actionable/rspec'

class LogCrossing < Actionable::Action
  input { optional :route, :string }

  fails :missing_route, 'a crossing needs a route'
  skips :already_logged

  step :check

  private

  def check
    fail!(:missing_route) if input.route.nil?
    succeed
  end
end

spec = Object.new.extend(Actionable::RSpec::Matchers, Actionable::RSpec::Stubs)

spec.perform_actionable(route: 'Quay-Isle').matches?(LogCrossing)                                # => true
spec.perform_actionable.and_fail(:missing_route, /needs a route/).matches?(LogCrossing)          # => true
spec.perform_actionable.and_skip(:already_logged).matches?(LogCrossing)                          # => false

begin
  spec.perform_actionable.and_fail(:missing_rout).matches?(LogCrossing)
rescue ArgumentError => e
  e.message.start_with?('LogCrossing does not declare :missing_rout')   # => true
end
```

## 4. Build a result without running anything

The builders return a real result, handy when you test code that only consumes one.

```ruby run
failure = spec.actionable_failure_result(code: :missing_route, errors: { route: 'is required' })
failure.code         # => :missing_route
failure.errors.to_h  # => {route: ["is required"]}
spec.actionable_skip_result(code: :already_logged).skipped?   # => true
spec.actionable_success_result(output: { leg: 4 }).output     # => {leg: 4}
```

## 5. Stub a collaborator action

When one action calls another, swap the collaborator out with `allow_actionable_failure`, `allow_actionable_success` or `allow_actionable_skip`. Each builds a real result and stubs `run` through rspec-mocks. The `stub_actionable_*` forms also expect the call to happen.

```ruby
RSpec.describe Embark do
  it 'stops when the deck is full' do
    allow_actionable_failure(ReserveBerth, code: :deck_full)

    expect(Embark).to perform_actionable(callsign: 'x').and_fail(:deck_full)
  end
end
```

A stubbed code that the collaborator doesn't declare raises, exactly like the matcher. And when the collaborator has an output schema, the stubbed output goes through it.

## See also

- [Testing](/reference/actionable/testing/)
- [Declare and handle outcomes](/how-to/handle-action-outcomes/)
- [Compose actions](/how-to/compose-actions/)
