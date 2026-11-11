---
title: "How to run an action in a background job"
description: "Retry a failed action by its code, discard the ones that can never succeed, and acknowledge the rest."
sidebar:
  label: "Run in a background job"
  order: 9
---

A `PullTimetable` job downloads a ferry timetable. A `:tide_late` answer deserves another try while `:garbled` never will, so the queue has to know which one it got.

## 1. Declare the codes and say which retry

Write the decision beside the code, as `retry:` metadata, and switch it on with `honor_retry_metadata`. The core never reads metadata by itself, so without that opt-in the job ignores it.

```ruby run
require 'actionable/job'

class PullTimetable < Actionable::Action
  honor_retry_metadata

  input { required :source, :string }

  fails :tide_late, retry: true
  fails :garbled, retry: false

  step :download

  private

  def download
    fail!(:tide_late) if input.source.include?('stalled')
    fail!(:garbled) if input.source.include?('scrambled')
    succeed('timetable loaded')
  end
end
```

## 2. Include the mixin in the job

`run_actionable` runs the action and keeps its result. It raises `Actionable::Job::RetryableFailure` when the result deserves a retry, and for an acknowledged or discarded one it simply returns the result, so the job ends.

ActiveJob needs to be told to retry that error. Sidekiq retries every job that raises, so there is nothing to add.

```ruby
class PullTimetableJob < ApplicationJob
  include Actionable::Job::Mixin
  retry_on Actionable::Job::RetryableFailure, wait: :polynomially_longer, attempts: 5

  def perform(source)
    result = run_actionable(PullTimetable, source: source)
    Rails.logger.warn("timetable dropped: #{result.code}") if result.failure?
  end
end
```

```ruby
class PullTimetableWorker
  include Sidekiq::Job
  include Actionable::Job::Mixin

  def perform(source)
    run_actionable(PullTimetable, source: source)
  end
end
```

## 3. See each disposition

No queue gem is needed to try the mixin. A plain object will do.

```ruby run
class TimetableRunner
  include Actionable::Job::Mixin

  def perform(source) = run_actionable(PullTimetable, source: source)
end

runner = TimetableRunner.new
runner.perform('https://example.org/quay.json').success?     # => true
runner.perform('https://example.org/scrambled').code         # => :garbled

begin
  runner.perform('https://example.org/stalled')
rescue Actionable::Job::RetryableFailure => e
  e.message      # => "actionable run failed with retryable code :tide_late"
  e.result.code  # => :tide_late
end
```

## 4. Change what counts as permanent

When `honor_retry_metadata` is off, every failure gets a retry unless its code is permanent. Out of the box the permanent codes are `:invalid_input`, `:invalid_output` and `:not_found`, because retrying input the action already refused can't change the answer. To use another list, override `actionable_permanent_codes`.

```ruby run
class PickyRunner
  include Actionable::Job::Mixin

  def actionable_permanent_codes = %i[garbled]
end

Actionable::Job.disposition(Actionable::Failure.new(code: :tide_late))                         # => :retry
Actionable::Job.disposition(Actionable::Failure.new(code: :invalid_input))                     # => :discard
Actionable::Job.disposition(Actionable::Failure.new(code: :tide_late), permanent: [:tide_late]) # => :discard
PickyRunner.new.actionable_permanent_codes   # => [:garbled]
```

An exception raised inside the action is not a failure. The mixin lets it through untouched, and your queue's usual retry rules take over.

## See also

- [Background jobs](/reference/actionable/jobs/)
- [Declared outcomes](/reference/actionable/declared-outcomes/)
- [Declare and handle outcomes](/how-to/handle-action-outcomes/)
