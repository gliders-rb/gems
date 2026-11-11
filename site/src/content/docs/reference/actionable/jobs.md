---
title: "Background jobs"
description: "Map an action's result to ack, discard or retry, and run actions inside Sidekiq or ActiveJob classes."
sidebar:
  order: 8
---

Inside your job class, the adapter runs an action and converts its result into a queue disposition. It is plain Ruby and wants neither queue gem (AC-B#jobpure). The run stays synchronous, and nothing gets enqueued by the adapter. Require it yourself:

```ruby
require 'actionable/job'
```

## `Job.disposition`

```ruby
Actionable::Job.disposition(result, permanent: DEFAULT_PERMANENT_CODES, honor_retry: false)
# => :ack | :discard | :retry
```

| Result | Disposition |
|---|---|
| success or skip | `:ack` |
| failure whose code is in `permanent` | `:discard` |
| any other failure | `:retry` |

`DEFAULT_PERMANENT_CODES` is `[:invalid_input, :invalid_output, :not_found]`, because retrying input the action already turned down can't help.

Pass `honor_retry: true` and the `retry` key in a failure's or skip's metadata settles the question on its own. Truthy means `:retry`, permanent code or not, skip or not. Falsy means `:discard` for a failure and `:ack` for a skip. A result without that key, and any success, follows the table above. Results that don't respond to `metadata` are never affected by the flag.

```ruby run
require 'actionable/job'

Actionable::Job::DEFAULT_PERMANENT_CODES # => [:invalid_input, :invalid_output, :not_found]

Actionable::Job.disposition(Actionable::Success.new)                       # => :ack
Actionable::Job.disposition(Actionable::Skipped.new)                       # => :ack
Actionable::Job.disposition(Actionable::Failure.new(code: :invalid_input)) # => :discard
Actionable::Job.disposition(Actionable::Failure.new(code: :rough_sea))       # => :retry

Actionable::Job.disposition(Actionable::Failure.new(code: :rough_sea), permanent: [:rough_sea]) # => :discard

flagged = Actionable::Failure.new(code: :invalid_input, metadata: { retry: true })
Actionable::Job.disposition(flagged, honor_retry: true) # => :retry
Actionable::Job.disposition(flagged)                    # => :discard

stop = Actionable::Failure.new(code: :rough_sea, metadata: { retry: false })
Actionable::Job.disposition(stop, honor_retry: true)    # => :discard
Actionable::Job.disposition(Actionable::Skipped.new(metadata: { retry: true }), honor_retry: true) # => :retry
```

## `honor_retry_metadata`

```ruby
honor_retry_metadata(enabled: true)
honor_retry_metadata?
```

Metadata-driven retries are opt-in per action, through `honor_retry_metadata`. The reader looks up the superclass chain at call time and answers `false` unless someone enabled it, and a subclass can switch it back off with `enabled: false`. The macro only exists on `Action` once the adapter is loaded. Without the opt-in a job ignores metadata, which is how the core keeps it opaque (AC-I7). You declare the metadata itself with `fails` (see [Declared outcomes](/reference/actionable/declared-outcomes/)).

```ruby run
require 'actionable/job'

class TideTable < Actionable::Action
  honor_retry_metadata
  fails :rough_sea, retry: true
  fails :smudged_chart, retry: false
end

class StrictTideTable < TideTable
  honor_retry_metadata(enabled: false)
end

TideTable.honor_retry_metadata?          # => true
StrictTideTable.honor_retry_metadata?        # => false
Actionable::Action.honor_retry_metadata?  # => false
TideTable.declared_failures              # => {rough_sea: {retry: true}, smudged_chart: {retry: false}}
```

## `Job::Mixin`

Mix `Actionable::Job::Mixin` into a Sidekiq worker or an ActiveJob class to get:

| Member | Meaning |
|---|---|
| `run_actionable(action_class, *args, **kwargs)` | run the action, keep the result, raise on `:retry`, otherwise return the result |
| `actionable_result` | the result of the last `run_actionable` |
| `actionable_permanent_codes` | the permanent list; override it to change the codes |

When the action responds to `honor_retry_metadata?`, `run_actionable` takes `honor_retry` from it. On `:ack` and `:discard` it hands back the result, so the job ends normally and the caller can decide whether a discard is worth logging. A real exception from inside the action passes through untouched. ActiveJob needs `retry_on Actionable::Job::RetryableFailure` declared, while Sidekiq already retries any job that raises.

```ruby
class TideTableJob < ApplicationJob
  include Actionable::Job::Mixin
  retry_on Actionable::Job::RetryableFailure, wait: :polynomially_longer

  def perform(harbour)
    run_actionable(TideTable, harbour: harbour)
  end
end
```

No queue gem is needed for the mixin, so a plain object will do for a try:

```ruby run
require 'actionable/job'

class Choppy < Actionable::Action
  fails :rough_sea
  step :sail

  private

  def sail = fail!(:rough_sea)
end

class DispatchWorker
  include Actionable::Job::Mixin

  def perform = run_actionable(Choppy)
end

worker = DispatchWorker.new
begin
  worker.perform
rescue Actionable::Job::RetryableFailure => e
  e.message      # => "actionable run failed with retryable code :rough_sea"
  e.result.code  # => :rough_sea
end
worker.actionable_result.failure? # => true
```

## `RetryableFailure`

`Actionable::Job::RetryableFailure.new(result)` is an `Actionable::Error` with a `result` reader. Its message reads `actionable run failed with retryable code :code` for a failure, and `actionable run skipped with retryable code :code` for a retried skip.

## See also

- [Declared outcomes](/reference/actionable/declared-outcomes/): where `retry:` metadata is declared
- [Errors and guardrails](/reference/actionable/errors/): the exception classes
- [Results](/reference/actionable/results/): `metadata` on failures and skips
