# Changelog

All notable changes to this gem are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the gem follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Actionable.register_step_option(name, owner:)` and `Actionable.registered_step_options`: an adapter or app
  registers the step option keys it reads.
- Descriptions: `desc 'text'` (or `description`) on an action, and `desc:` on steps, `case_step`, branches, hooks
  (`after_commit` too) and `fails`/`skips`. On `fails`/`skips` it is kept out of the metadata. `describe` has a
  `description` key, and each step, failure and skip entry carries `description:`.

### Changed

- `describe[:hooks]` lists step entries (`{type:, name:, options:, description:}`) instead of names, the same shape
  as `describe[:steps]`. A guarded step or hook entry carries `guard:` with readable labels, and a case step's entry
  carries `branches:` (`[{on:, step:}]`) and `default:`.
- An unknown step option key now raises `DefinitionError` when the step, hook, `case_step` or branch is declared,
  with a did-you-mean (`unknown step option iff: on Charge#charge (did you mean if:?)`). Before, `step :x, iff: ...`
  was accepted and the step always ran. A case branch's guard type is checked at declaration too.

- A result's `to_h` starts with `status:`, and its `as_json` and `to_json` now carry `status` and `errors` too, with
  the same keys in the same order as `to_h`. Before, the JSON form held the code but not the status or the errors.

### Fixed

- `sig/`: the verbs are declared as private methods of `Actionable::Verbs`, so step bodies that call `succeed`,
  `fail!`, `skip` and the rest type-check (with Steep, `fail` was `Kernel#fail`).
- `sig/manifest.yaml` names `field_struct` and `prism`, so the sig loads with `rbs -r actionable-rb` or an RBS
  collection.
- `sig/` no longer names Rails, ActiveModel, RuboCop or LintRoller, so it loads in an app without them: `Railtie`,
  `RubocopPlugin` and the `VerbNotLast` cop are declared without their framework parents, `ProxyValidator` without
  `include ActiveModel::Validations`, and `model_name` and the plugin's `about`, `supported?` and `rules` (called only
  by those frameworks) are left out. Ruby is unchanged. To call `valid?` or `errors` on a validator under Steep, add
  `include ::ActiveModel::Validations` to `Actionable::ProxyValidator` in your own sig.
- `BatchResult#successes`, `#failures` and `#skips` now type-check as `Array[Success]`, `Array[Failure]` and
  `Array[Skipped]` (the lists are unchanged).

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
