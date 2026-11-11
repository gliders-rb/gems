---
title: "OpenTelemetry"
description: "Give each action run a span, and each step a child span, that carry the outcome and the code but never a value."
sidebar:
  badge:
    text: Unreleased
    variant: caution
  label: "OpenTelemetry"
  order: 4
---

With `actionable-otel`, each `.run` opens a span and each step or hook that executes opens a child span. The outcome and the result code go on as attributes, and a declared failure flags its span as an error. Input values and output values are never recorded.

```ruby
gem 'actionable-otel'
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'
```

The gem depends on `opentelemetry-api` alone. Which SDK and exporter to use is up to your application.

:::caution
This adapter differs from the others: `require 'actionable/otel'` changes behaviour by switching tracing on for every action. The core gem never loads OpenTelemetry by itself.
:::

```ruby
require 'opentelemetry/sdk'
require 'actionable/otel'

OpenTelemetry::SDK.configure { |c| c.service_name = 'apiary-rounds' }
```

## What a run looks like

To see all of it, we need an action with three steps plus a success hook, a failure hook and an `always` hook. Spans here go to the SDK's in-memory exporter so we can read them back. A real app would point the OTLP exporter at a collector.

```ruby run
require 'opentelemetry/sdk'
require 'actionable/otel'

exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
OpenTelemetry::SDK.configure do |c|
  c.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter))
end

class ColonyRound < Actionable::Action
  fails :swarmed

  step :lift_lid
  step :tally_brood
  step :seal_up
  on_success :log_honey
  on_failure :flag_for_split
  always :stamp_ledger

  private

  def lift_lid = @lid_up = true
  def tally_brood = fail!(:swarmed)
  def seal_up = @sealed = true
  def log_honey = @logged = true
  def flag_for_split = @flagged = true
  def stamp_ledger = @stamped = true
end

ColonyRound.run.code   # => :swarmed

spans = exporter.finished_spans
# the run span closes last, so it is last
spans.last.name                                          # => "ColonyRound.run"
spans.last.attributes['actionable.outcome']              # => "failure"
spans.last.attributes['actionable.code']                 # => "swarmed"
spans.last.status.description                            # => "swarmed"
```

A tracing backend would draw that run like this:

```
ColonyRound.run              outcome=failure code=swarmed  status=ERROR(swarmed)
  ColonyRound/lift_lid       section=main
  ColonyRound/tally_brood    section=main code=swarmed
  ColonyRound/flag_for_split section=failure
  ColonyRound/stamp_ledger   section=always
```

`seal_up` has no span because it never ran: `fail!` stopped the main steps first. The failure hook ran where the success hook would have, and `always` runs either way. A run that succeeds has no error status.

```ruby run
spans.map(&:name)   # => ["ColonyRound/lift_lid", "ColonyRound/tally_brood", "ColonyRound/flag_for_split", "ColonyRound/stamp_ledger", "ColonyRound.run"]
spans[1].attributes['actionable.code']        # => "swarmed"
spans[2].attributes['actionable.section']     # => "failure"
spans[0].attributes['actionable.step.kind']   # => "method"
```

## Spans and attributes

| Span | Name | Attributes |
|---|---|---|
| run | `<Class>.run` | `actionable.action`, then `actionable.outcome` (`success`, `failure`, `skipped`) and `actionable.code` when the run returns |
| step or hook | `<Class>/<name>` | `actionable.action`, `actionable.step`, `actionable.step.kind` (`method`, `action`, `case`), `actionable.section` (`main`, `success`, `failure`, `skip`, `always`), and `actionable.code` when the step recorded a result |

- An anonymous action carries the label `Actionable::Action`.
- A step that runs a nested action takes the child class's name, and the child's run span sits beneath it.
- A case step is a single span, with the chosen branch running inside it.
- A step held back by an `if:` or `unless:` guard gets no span.
- A skip is not an error, but a declared failure is, so it counts toward your error rate. To tell declared failures from exceptions, filter on `actionable.code`.

The action's `measure` mode has no effect on spans, and sampling belongs to the SDK. A run stubbed through the `actionable/rspec` stubs emits no span.

## What is never recorded

A span never sees input fields, output fields, messages, error text or metadata. Everything named in a span is a class, a step, a section, an outcome or a result code.

Codes go in exactly as written, so keep them fixed. Something like `fail!(:"rejected_#{reason}")` would put a changing value into every trace and inflate the count of distinct attribute values. When you need an attribute of your own, set it on the current span from inside a step.

## Exceptions

When an exception escapes a run, it is recorded once, on the run span, and then raised again as it was. The event holds only the exception class by default, since messages and backtraces can contain input values. A declared failure counts as a normal result and adds no exception event.

```ruby run
class Collapse < Actionable::Action
  step :crack_frame

  private

  def crack_frame = raise('tag fr_4411 cracked')
end

exporter.reset
begin
  Collapse.run
rescue RuntimeError => e
  e.message   # => "tag fr_4411 cracked"
end

event = exporter.finished_spans.last.events.first
event.name         # => "exception"
event.attributes   # => {"exception.type" => "RuntimeError"}
```

The trace never got the message, though the application still did.

## Settings

Both settings are process-wide, so set them once at boot.

| Setting | Default | Meaning |
|---|---|---|
| `Actionable::Otel.step_spans = false` | `true` | emit run spans only, no step or hook spans |
| `Actionable::Otel.exception_details = :full` | `:type_only` | also record the exception message and stacktrace |

```ruby run
Actionable::Otel.step_spans?          # => true
Actionable::Otel.step_spans = false
Actionable::Otel.step_spans?          # => false
Actionable::Otel.step_spans = true

Actionable::Otel.exception_details    # => :type_only

begin
  Actionable::Otel.exception_details = :message
rescue ArgumentError => e
  e.message   # => "Actionable::Otel.exception_details must be :type_only or :full, got :message"
end
```

## Cost and volume

A run costs one span, and every step or hook that executes costs one more. With no SDK installed, OpenTelemetry's no-op provider swallows the spans and the overhead stays small. The provider is looked up when a run starts, so one installed after `actionable/otel` loaded takes effect on the next run. If volume gets too high, set `step_spans = false` or sample in the SDK.

## Compatibility

You need Ruby 3.3 or newer, `actionable-rb` 2.x and `opentelemetry-api` 1.7 or newer. The adapter wraps `Action.run` and one internal method of the runner, so a new major of `actionable-rb` may call for a new release here.

## See also

- [Hooks and history](/reference/actionable/hooks-and-history/): the sections that become `actionable.section`
- [Declared outcomes](/reference/actionable/declared-outcomes/)
- [How adapters work](/adapters/how-adapters-work/)
