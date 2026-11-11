# Changelog

All notable changes to this gem are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the gem follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0.pre1]

First release of the 2.0 line. The test suite is organized by numbered behaviour rules (`AC-B#…`), so every
example names the rule it proves.

### Added

- `Actionable::Action` with `step`, `case_step`, the four hook macros, `input`, `input_for`, `output`, `fails`,
  `skips`, `measure` and `typed_outcomes`, and the verbs `succeed`, `fail`, `skip`, `fail_with` and their bang forms.
- `Success`, `Failure` and `Skipped` results (FieldStruct classes) with a code, message, errors, output, history and,
  for failures and skips, metadata. `BatchResult`, `Registry`, `History`, `describe` and `describe_text`.
- Control flow by `throw` and `catch`. Genuine exceptions are never rescued.
- Declared failure and skip codes with default messages, opaque metadata and optional per-code output schemas.
- Typed outcomes: per-action result classes and per-code output contracts.
- The first-run verb-position check (Prism) and the `Actionable/VerbNotLast` RuboCop cop.
- Opt-in adapters: `actionable/rails` (transactions, `after_commit`, `ProxyValidator`), `actionable/job`,
  `actionable/rspec` (matcher and stubs) and `actionable/rspec/coverage` (outcome coverage with a baseline).
- `Actionable::RBS.generate` for the RBS of your own actions, and shipped signatures in `sig/`.
- `USAGE.md`, `docs/getting_started.md`, `AGENTS.md`, a Claude Code skill and plugin manifest.
- Development tooling: doctests for the docs, a generated and checked signature file with an `untyped` ratchet, YARD
  completeness, benchmarks, and `rake release:check`.
