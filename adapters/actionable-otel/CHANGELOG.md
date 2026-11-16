# Changelog

## [Unreleased]

### Changed

- The tracing hooks `trace_run`, `trace_step`, `tracer` and `label_for` are marked `@api private` in their YARD
  comments: the prepended module calls them, and they aren't part of the public API.

## 1.0.0.pre1

- First release: OpenTelemetry spans for actionable-rb. One span per `Action.run`, a child span per executed step and hook,
  `actionable.outcome` and `actionable.code` attributes, declared failures marked as errors, and never an input or output value.
