# actionable-otel

OpenTelemetry tracing for [actionable-rb](../../gems/actionable). One span per `.run`, a child span per executed step
and hook, the outcome and result code as attributes, and declared failures marked as errors. It never records an input
or output value.

Requiring it turns tracing on. The core gem never loads OpenTelemetry. The gem depends on `opentelemetry-api` only: the
SDK and the exporter are your application's choice.

## Install

```ruby
gem 'actionable-otel'
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'
```

```ruby
require 'opentelemetry/sdk'
require 'actionable/otel'
OpenTelemetry::SDK.configure { |c| c.service_name = "apiary" }
```

## What a run looks like

<!-- doctest -->
```ruby
require 'opentelemetry/sdk'
require 'actionable/otel'

exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
OpenTelemetry::SDK.configure do |c|
  c.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter))
end

class HiveInspection < Actionable::Action
  fails :queen_missing

  step :open_hive
  step :count_frames
  on_success :file_report
  on_failure :reseal_hive
  always :stamp_log

  private

  def open_hive = @opened = true
  def count_frames = fail!(:queen_missing)
  def file_report = @filed = true
  def reseal_hive = @resealed = true
  def stamp_log = @stamped = true
end

HiveInspection.run.code # => :queen_missing
spans = exporter.finished_spans
spans.map(&:name) # => ["HiveInspection/open_hive", "HiveInspection/count_frames", "HiveInspection/reseal_hive", "HiveInspection/stamp_log", "HiveInspection.run"]
run = spans.last
run.attributes['actionable.outcome'] # => "failure"
run.attributes['actionable.code'] # => "queen_missing"
run.status.description # => "queen_missing"
spans[1].attributes['actionable.code'] # => "queen_missing"
spans[2].attributes['actionable.section'] # => "failure"
```

The trace of that run:

```
HiveInspection.run              outcome=failure code=queen_missing   status=ERROR(queen_missing)
  HiveInspection/open_hive  section=main
  HiveInspection/count_frames    section=main code=queen_missing
  HiveInspection/reseal_hive  section=failure
  HiveInspection/stamp_log          section=always
```

A success has no error status, and its outcome hook (`file_report`) takes the failure hook's place.

## Spans and attributes

| Span | Name | Attributes |
|---|---|---|
| run | `<Class>.run` | `actionable.action`, then `actionable.outcome` (`success`, `failure`, `skipped`) and `actionable.code` when the run returns |
| step or hook | `<Class>/<name>` | `actionable.action`, `actionable.step`, `actionable.step.kind` (`method`, `action`, `case`), `actionable.section` (`main`, `success`, `failure`, `skip`, `always`), and `actionable.code` when the step recorded a result |

An anonymous action is labelled `Actionable::Action`. A nested action step is named after the child class, and the
child's run span nests under it. A case step is one span; the branch it picks runs inside it. Steps skipped by an
`if:` or `unless:` guard get no span. A skip is not an error; a declared failure is, so error rates include it. Filter
by `actionable.code` to tell declared failures from exceptions.

Spans are emitted whatever the action's `measure` is; sampling is the SDK's job. A run stubbed with the
`actionable/rspec` stubs emits no span.

## Settings

Process-wide.

<!-- doctest -->
```ruby
require 'opentelemetry'
require 'actionable/otel'

Actionable::Otel.step_spans? # => true
Actionable::Otel.step_spans = false # run spans only
Actionable::Otel.step_spans? # => false
Actionable::Otel.exception_details # => :type_only
Actionable::Otel.exception_details = :full
Actionable::Otel.exception_details # => :full
begin
  Actionable::Otel.exception_details = :message
rescue ArgumentError => e
  e.message # => "Actionable::Otel.exception_details must be :type_only or :full, got :message"
end
```

## Exceptions

An exception that escapes a run is recorded once, on the run span, and re-raised unchanged. By default the event holds
the exception class only (`exception.type`), because messages and backtraces can hold input values.
`exception_details = :full` records the message and stacktrace too. A declared failure is a normal result: it records
no exception event.

## What is never recorded

Input fields, output fields, messages, error text and metadata. Result codes are recorded as they are, so keep them
static: `fail!(:"swarmed_#{hive}")` would leak and explode cardinality. Add your own attributes in a step if you need
them.

## Compatibility

Ruby 3.3+, `actionable-rb` `>= 2.0.0.pre1, < 3` (the gem wraps `Action.run` and the runner's internal `record` seam, so
a major release may move it), `opentelemetry-api` `~> 1.7`.
