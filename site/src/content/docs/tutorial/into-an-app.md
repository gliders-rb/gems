---
title: "Into an app"
description: "Call an action from a controller and return JSON, handle a pass-report lookup that times out, retry it in a job and write a spec."
sidebar:
  label: "6. Into an app"
  order: 7
---

The trek planner works in a console. In this last chapter we put it behind a web endpoint: a controller that returns JSON, a pass-report lookup that sometimes times out, a background job that retries it, and a spec.

## Where we left off

We had a plan built from small actions. Here is a slimmer version, with a lookup that asks another service how much snow lies on a pass. The service is a stand-in object, since the tutorial never touches the network. While `PassReport.down` is true the lookup raises `Timeout::Error`, the way a slow HTTP call would.

```ruby run title="plan_trek.rb"
require 'timeout'
require 'json'

FREE = { 'KR12' => 5 }

module PassReport
  class << self
    attr_accessor :down

    def snow_cm_for(pass)
      raise Timeout::Error, 'pass report timed out' if down

      { 'Larch' => 12, 'Eagle' => 40 }[pass]
    end
  end
end

class CheckPass < Actionable::Action
  input { required :pass, :string }
  output { required :snow_cm, :integer }

  fails :unknown_pass, 'no report covers that pass', retry: false
  fails :report_timeout, 'the pass report did not answer', retry: true

  step :look_up

  private

  def look_up
    depth = PassReport.snow_cm_for(input.pass)
    fail!(:unknown_pass) unless depth
    @snow_cm = depth
  rescue Timeout::Error
    fail!(:report_timeout)
  end
end

class PlanTrek < Actionable::Action
  input do
    required :hut_code, :string
    required :places, :integer, in: 1..10
    required :pass, :string
  end

  output do
    required :snow_cm, :integer
  end

  fails :fully_booked, 'not enough places free', retry: false
  fails :unknown_pass, 'no report covers that pass', retry: false
  fails :report_timeout, 'the pass report did not answer', retry: true

  step :check_availability
  step :prepare
  step CheckPass, input: %i[pass], expose: %i[snow_cm]
  step :reserve

  private

  def check_availability
    fail!(:fully_booked) if FREE.fetch(input.hut_code, 0) < input.places
  end

  def prepare
    @pass = input.pass
  end

  def reserve
    FREE[input.hut_code] -= input.places
  end
end
```

The lookup turns the exception it expects into a named failure, `:report_timeout`, with `retry: true` in its metadata. An exception it doesn't expect still propagates, as chapter 4 showed.

## Call it from a controller

A controller turns params into an action call and a result into a response. This one is a plain class so the example runs anywhere. In Rails the shape is the same, with `params.to_unsafe_h` or a permitted hash where we use a plain one.

```ruby run title="treks_controller.rb"
class TreksController
  STATUS = { fully_booked: 409, unknown_pass: 422, report_timeout: 503, invalid_input: 422 }.freeze

  def create(params)
    result = PlanTrek.run(**params)

    case result
    in Actionable::Success
      [201, JSON.generate(snow_cm: result.snow_cm)]
    in Actionable::Failure
      [STATUS.fetch(result.code, 500), JSON.generate(error: result.code, message: result.message, fields: result.errors.to_h)]
    end
  end
end

controller = TreksController.new

status, body = controller.create(hut_code: 'KR12', places: '1', pass: 'Eagle')
status                               # => 201
JSON.parse(body)                     # => {"snow_cm" => 40}

status, body = controller.create(hut_code: 'KR12', places: '1', pass: 'Nowhere')
status                               # => 422
JSON.parse(body)['error']            # => "unknown_pass"

status, body = controller.create(hut_code: 'KR12', places: '99', pass: 'Larch')
status                               # => 422
JSON.parse(body)['fields']           # => {"places" => ["is invalid"]}
```

Params go in with `**`. A single positional hash is ignored, and every field would read as missing.

## A collaborator that times out

Now we make the pass report slow.

```ruby run
PassReport.down = true

status, body = TreksController.new.create(hut_code: 'KR12', places: '1', pass: 'Eagle')
status                               # => 503
JSON.parse(body)['error']            # => "report_timeout"
FREE['KR12']                         # => 4
```

The controller answered 503, which tells a client to try again later. The action didn't blow up, and the response was built from a value.

The free count is still 4, which is what the earlier successful plan left. The lookup runs before `reserve`, so the timeout took nothing, and that is what makes `retry: true` honest. A failure that carries it is safe to run again.

## Retry in a job

A timeout is worth another try and an unknown pass is not. The metadata we declared says which is which. `actionable/job` turns a result into `:ack`, `:discard` or `:retry`, and the mixin does it inside your job class.

```ruby run title="plan_trek_job.rb"
require 'actionable/job'

class PlanTrek
  honor_retry_metadata
end

class PlanTrekJob
  include Actionable::Job::Mixin

  def perform(**params)
    run_actionable(PlanTrek, **params)
  end
end

job = PlanTrekJob.new
trek = { hut_code: 'KR12', places: 1, pass: 'Eagle' }

begin
  job.perform(**trek)
rescue Actionable::Job::RetryableFailure => e
  e.result.code    # => :report_timeout
end
```

While the service is down, `perform` raises `RetryableFailure`. Your queue sees an exception and retries on its own schedule. With ActiveJob you add `retry_on Actionable::Job::RetryableFailure` to the class, and Sidekiq retries any raise by default.

Once the service is back, a retry succeeds. An `:unknown_pass` failure comes back as a result instead, so the job finishes and the queue forgets it.

```ruby run
PassReport.down = false

job.perform(**trek, pass: 'Nowhere').code   # => :unknown_pass
job.perform(**trek).success?                # => true
FREE['KR12']                                # => 3
```

## Test it

The `perform_actionable` matcher runs an action and checks its outcome in one line. In a real suite you require `actionable/rspec` and write `expect(...).to perform_actionable(...)`. The matcher also works on its own, so here we check it on a small stand-in for an example group.

```ruby run
require 'actionable/rspec'

spec = Object.new.extend(Actionable::RSpec::Matchers)

spec.perform_actionable(hut_code: 'KR12', places: 1, pass: 'Larch').matches?(PlanTrek)                                  # => true
spec.perform_actionable(hut_code: 'KR12', places: 1, pass: 'Nowhere').and_fail(:unknown_pass).matches?(PlanTrek)        # => true
spec.perform_actionable(hut_code: 'KR12', places: 99, pass: 'Larch').and_fail(:invalid_input).matches?(PlanTrek)        # => true
```

Specs for the timeout shouldn't lean on a real slow service. Stub the child action and the parent sees the failure you chose. These examples need RSpec's mocks, so they're plain code here.

```ruby
require 'actionable/rspec'

RSpec.describe PlanTrek do
  it 'reports a pass-report timeout' do
    allow_actionable_failure(CheckPass, code: :report_timeout)

    expect(PlanTrek).to perform_actionable(hut_code: 'KR12', places: 1, pass: 'Eagle')
      .and_fail(:report_timeout)
  end

  it 'carries the retry metadata' do
    allow_actionable_failure(CheckPass, code: :report_timeout)

    result = PlanTrek.run(hut_code: 'KR12', places: 1, pass: 'Eagle')
    expect(result.metadata).to eq(retry: true)
  end
end
```

`allow_actionable_failure` builds a real `Failure`, with the declared message and metadata for that code, so the stub can't drift from the action. Asking for a code the action doesn't declare raises in the spec itself.

## What you built

A trek planner from `Hut` to a job and a spec: typed structs, JSON, actions with named outcomes, composition with an undo, a controller that maps codes to statuses, a flaky lookup turned into a retryable failure, and specs that don't need the network.

From here, pick what you need.

## See also

- [How-to guides](/how-to/): one task each, from validating params to RuboCop
- [Run in a background job](/how-to/background-jobs/)
- [Test with RSpec](/how-to/test-with-rspec/)
- [Reference](/reference/): every option and method
