---
title: "Testing"
description: "The perform_actionable matcher, result builders, collaborator stubs and outcome coverage for testing actions."
sidebar:
  order: 10
---

Testing takes two requires. `actionable/rspec` brings the matcher and the stub helpers, and `actionable/rspec/coverage` keeps track of which declared outcomes your suite reached. The core loads neither (AC §5.18, §5.19).

```ruby
require 'actionable/rspec'
require 'actionable/rspec/coverage'
```

If `RSpec` is defined, requiring `actionable/rspec` mixes both modules into every example group. Inside `module Actionable` the name `RSpec` resolves to `Actionable::RSpec`, so write `::RSpec` for the framework.

Examples that need RSpec's mocks are plain code blocks here. The matcher, the result builders and coverage work without a framework, so those examples run on a small object that extends the modules. In a real suite you call the same methods straight from an example.

```ruby run
require 'actionable/rspec'

class ClearBerth < Actionable::Action
  input { required :berth, :string }
  fails :occupied, 'berth is occupied'
  skips :already_free

  step :inspect_berth

  private

  def inspect_berth
    skip!(:already_free) if input.berth == 'free'
    fail!(:occupied)
  end
end

# in a spec, these methods are already available
example = Object.new.extend(Actionable::RSpec::Matchers, Actionable::RSpec::Stubs)
```

## `perform_actionable`

```ruby
expect(ActionClass).to perform_actionable(*args, **kwargs).and_fail(:code, /message/)
```

You apply the matcher to an action class. It calls `.run(*args, **kwargs)` and catches a raised `StandardError` rather than letting it out. Used bare, it expects a success. A chain selects the outcome instead, and the last chain wins. Every chain accepts an optional block, which receives `(result_or_nil, exception_or_nil)` after the primary match and has to return something truthy.

| Chain | Passes when |
|---|---|
| `and_succeed(message = nil)` | no exception, a success, and the message matches |
| `and_fail(code = nil, message = nil)` | a failure, with the code `==` and the message matching when given |
| `and_skip(code = nil, message = nil)` | a skip, with the same checks |
| `and_raise(error_class = StandardError, message = nil)` | an exception of that kind, with a matching message |

Messages are compared with `===`, so a String, a Regexp or a class all work, and `nil` skips the check. To the matcher a skip is neither a success nor a failure. `does_not_match?` negates the primary match alone and ignores the block.

```ruby run
matcher = example.perform_actionable(berth: 'B7').and_fail(:occupied, /occupied/)
matcher.matches?(ClearBerth)   # => true
matcher.description            # => "perform actionable and fail"

example.perform_actionable(berth: 'free').and_skip(:already_free).matches?(ClearBerth) # => true
example.perform_actionable(berth: 'B7').and_succeed.matches?(ClearBerth)               # => false
```

A mismatch produces the message `expected <Action> to <phrase>, but <actual>`. The actual part is the result's `inspect`, or `it raised <Class>: <message>` followed by the backtrace, or `no result was produced`. The backtrace is complete unless `ACTIONABLE_SHORT_BACKTRACE` is set, which cuts it to the first `ACTIONABLE_BACKTRACE_QTY` frames (10 by default).

```ruby run
failing = example.perform_actionable(berth: 'B7').and_succeed
failing.matches?(ClearBerth)
failing.failure_message.start_with?('expected ClearBerth to succeed, but got #<Actionable::Failure') # => true
```

### Declared codes are checked

Say the expected code is a Symbol and the action declares codes of that kind. A code it didn't declare raises `ArgumentError`, negated expectations included. That is a broken spec rather than a mismatch, since the test would assert an outcome the action can never produce. Failures may also use the gem's own codes, a bare `and_fail` or `and_skip` always passes this check, and an action that declares none accepts any code.

```ruby run
begin
  example.perform_actionable(berth: 'B7').and_fail(:flotsam).matches?(ClearBerth)
rescue ArgumentError => e
  e.message # => "ClearBerth does not declare :flotsam (declared: :occupied); a stub or and_fail with it tests a failure the action can never return"
end
```

## Result builders

Each builder returns a real result, with nothing stubbed.

| Builder | Defaults |
|---|---|
| `actionable_success_result(message: nil, output: {}, errors: {})` | a `Success` |
| `actionable_failure_result(code: :error, message: nil, output: {}, errors: {}, metadata: {})` | a `Failure` |
| `actionable_skip_result(code: :skipped, message: nil, output: {}, metadata: {})` | a `Skipped` |

Values given to `errors:`, a String or an Array, are added to the result's errors.

```ruby run
failure = example.actionable_failure_result(code: :occupied, errors: { berth: 'is wrong' })
failure.code             # => :occupied
failure.errors.to_h      # => {berth: ["is wrong"]}
example.actionable_success_result(output: { slot: 1 }).output # => {slot: 1}
example.actionable_skip_result.code                         # => :skipped
```

## Stubs

```ruby
allow_actionable_success(action, message:, output:, errors:)
allow_actionable_failure(action, code: :error, message:, output:, errors:, metadata:)
allow_actionable_skip(action, code: :skipped, message:, output:, metadata:)
stub_actionable_success(...)   # also: stub_actionable_failure, stub_actionable_skip
```

`allow_*` lets `action.run` through rspec-mocks, and `stub_*` also expects the call to happen. Both build a real result, stub `run` to return it whatever the arguments, and hand the result back. They replace a child action or a collaborator inside the action under test.

```ruby
RSpec.describe BookCrossing do
  it 'stops when the deck is full' do
    allow_actionable_failure(HoldBerth, code: :deck_full)

    expect(BookCrossing).to perform_actionable(berth: 'B7').and_fail(:deck_full)
  end

  it 'passes the hold through' do
    stub_actionable_success(HoldBerth, output: { ticket_no: 7 })

    expect(BookCrossing.run(berth: 'B7').ticket_no).to eq(7)
  end
end
```

Where the action declares failures, a stubbed failure takes the declared metadata, and the declared message when you pass none. Metadata you pass explicitly beats the declared one. A code the action didn't declare raises the same `ArgumentError` as the matcher, with gem codes allowed. Skips work the same way, except the default `:skipped` gets no exemption: `allow_actionable_skip(action)` raises unless the action declares `:skipped` or declares no skips at all.

What the stub returns as output depends on the action. Without typed outcomes you get exactly what you passed, so a Hash stays a Hash: `result.output[:id]` works and `result.id` doesn't. With typed outcomes, and for any code that has an output schema, the output goes through the schema the way a real run would shape it. Output that breaks the schema raises `ArgumentError`, saying a real run would end as `invalid_output`, and so does output for a code with no schema. When a parent's action step absorbs a stubbed child, only the fields you gave the stub come through (AC-B#stubshape, AC-B#stubparent).

## Outcome coverage

```ruby
require 'actionable/rspec/coverage'
```

After the require, each real `.run` of a named action is recorded as `[name, outcome, code]`, nested action steps and `run_each` items included, and a single `after(:suite)` hook prints the declared outcomes that no spec reached. Anonymous classes don't count. A stub of `run` on the subclass sits in front of the recorder, so stubbed runs never count as real. The stub helpers log them separately, and the report shows them as `Stubbed only`.

An action's expected outcomes are `"success"`, `"failure:<code>"` per declared failure, `"skipped:<code>"` per declared skip, and whichever gem codes you configure.

```ruby run
require 'actionable/rspec/coverage'

Actionable::Coverage.reset!
Actionable::Coverage.expected_outcomes(ClearBerth) # => ["success", "failure:occupied", "skipped:already_free"]

ClearBerth.run(berth: 'free')
Actionable::Coverage.observed.to_a # => [["ClearBerth", :skipped, :already_free]]
Actionable::Coverage.actions       # => [ClearBerth]

report = Actionable::Coverage::Report.new
report.to_baseline  # => {"ClearBerth" => ["success", "failure:occupied"]}
report.totals       # => {actions: 1, expected: 3, reached: 1, missing: 2}
report.passed?      # => true
report.to_s.lines.first.chomp # => "Actionable outcome coverage"
report.to_s.lines.last.chomp  # => "Actions: 1  Expected outcomes: 3  Reached: 1  Missing: 2"
```

Gem codes only count once configured, and the setter turns down anything other than the gem's two codes:

```ruby run
Actionable::Coverage.gem_codes = %i[invalid_input]
Actionable::Coverage.expected_outcomes(ClearBerth).last # => "failure:invalid_input"
Actionable::Coverage.gem_codes = []

begin
  Actionable::Coverage.gem_codes = %i[occupied]
rescue ArgumentError => e
  e.message # => "not a gem failure code: :occupied (the gem emits :invalid_input, :invalid_output)"
end
```

### Settings

| Setting | Default | Meaning |
|---|---|---|
| `root` | `Actionable::Action` | descendants of this class are reported |
| `include_prefixes`, `exclude_prefixes` | `[]` | name prefixes (Strings) or Regexps; any include filter restricts to matches |
| `loader` | none | a callable run before listing, such as an eager load |
| `gem_codes` | `[]` | gem codes to expect: `:invalid_input` applies to a schema with a required field, `:invalid_output` when a schema a run is held to has one |
| `only_observed` | `false` | drop actions with no real run, for a local partial run |
| `baseline` | `nil` | path to the baseline file |
| `new_gap_hint` | `DEFAULT_NEW_GAP_HINT` | the hint line in a baseline mismatch message |

`Coverage.reset_config!` puts the defaults back. The recording side offers `observed`, `stubbed` (both return copies), `record`, `record_stub`, `reset!`, `enable!`, `disable!` and `enabled?`. A disabled recorder does nothing but stays installed. `Coverage.actions` walks `subclasses` instead of the registry, keeps classes with at least one step whose name still resolves to that class, and sorts them by name.

### Reports and baselines

`Coverage.report!(files: [], io: $stdout)` builds and prints the report. Then it either rewrites the baseline, when `ACTIONABLE_COVERAGE_UPDATE_BASELINE` is `true`, or raises `Coverage::BaselineMismatch` carrying `baseline_message` if the report doesn't pass. The report is returned. Set `ACTIONABLE_COVERAGE_JSON` to a path and the JSON form is written there as well.

A `Report` responds to `rows` (per action: `action`, `expected`, `reached`, `missing`, `stubbed_only`), `totals`, `new_gaps`, `stale`, `passed?`, `baseline_message`, `to_baseline`, `write_baseline(path)`, `to_h` and `to_json`. With no baseline, missing outcomes never fail the report. With a baseline (YAML for `.yml` or `.yaml`, otherwise JSON through Oj), a gap that isn't listed is a `new_gap`, and an entry for an action that vanished or an outcome that is no longer a gap is `stale`. `passed?` wants both lists empty, so a fixed gap can't mask a new one. A baseline path that doesn't exist raises `Actionable::Error`.

Parallel suites use `Coverage.write(path)`, which saves this process's runs, and `Coverage.read(path)`, which loads them back as `{observed:, stubbed:}` sets. If `ACTIONABLE_COVERAGE_FILE` names a path, the suite hook writes a shard there and prints nothing, since a single shard can't judge the whole suite. Give each process its own path and merge them with `Coverage.report!(files: 'tmp/coverage/*.json')`.

:::caution
A baseline is only meaningful for a full run. Set it in CI, and use `only_observed` for a partial run on your machine.
:::

```ruby
Actionable::Coverage.baseline = 'spec/coverage_baseline.yml' # CI only
Actionable::Coverage.only_observed = true                    # local partial run
```

## See also

- [Declared outcomes](/reference/actionable/declared-outcomes/): the codes that the matcher and coverage check against
- [Results](/reference/actionable/results/): what the builders return
- [Errors and guardrails](/reference/actionable/errors/): `BaselineMismatch` and the `ArgumentError` cases
