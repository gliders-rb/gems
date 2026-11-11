# Changelog

All notable changes to this gem are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the gem follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0.pre1]

First release of the 1.0 line. The test suite is organized by numbered behaviour rules (`FS-B…`), so every example
names the rule it proves.

### Added

- `FieldStruct::Base` with `field`, `required` and `optional`: typed readers and permissive, coercing writers that
  record errors instead of raising.
- Types: `string`, `immutable_string`, `uuid`, `url`, `email`, `binary`, `symbol`, `integer`, `float`, `decimal`
  (`big_decimal`), `boolean`, `date`, `time`, `datetime`, `value`, `array`, `union`, and nested structs.
- Options: `default`, `coercion_policy`, `description`, `rbs_type`, `sensitive`, and per-type `format`, `enum`, `in`,
  `base`, `round`, `strict`, `values`, `zone`, `of` and `element`; pass-through options for exporters.
- Class settings: `coercion_policy`, `unknown_attributes`, `immutable!`, `frozen!`, `validate`, `serialize`, and `with`.
- JSON through Oj: `as_json`, `to_json`, `from_json`, with per-format key mappings that apply in both directions.
- Zones for `time` and `datetime` (`UTC`, fixed offsets, IANA names through `tzinfo`, loaded only when used).
- Registries for custom types, with namespace lookup through a module's `field_types`.
- `describe`, `Metadata#to_h`, `inspect` with sensitive-field masking, `use_alias!`.
- `FieldStruct::Introspection`, a read-only walk of a struct's fields for schema exporters.
- `FieldStruct::RBS` to generate signatures for your own models, and `FieldStruct::Scaffold` to generate a model from
  sample JSON.
- Shipped signatures (`sig/field_struct.rbs`), `USAGE.md`, `docs/getting_started.md`, `AGENTS.md`, and a Claude Code
  skill and plugin manifest.
- Development tooling: README doctests, a generated and checked signature file, YARD completeness, benchmarks, and
  `rake release:check`.
