# Changelog

## 1.0.0.pre1

- First release: OpenTelemetry spans for actionable-rb. One span per `Action.run`, a child span per executed step and hook,
  `actionable.outcome` and `actionable.code` attributes, declared failures marked as errors, and never an input or output value.
