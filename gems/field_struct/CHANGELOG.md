# Changelog

All notable changes to this gem are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the gem follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `mirror!` (read with `mirror?`): a field of a mirror type reads any object into it, one public reader per declared
  field; a missing reader raises. `max_items:` on `:array` is a field error past the limit, and lets an array of
  mirrors read a lazy collection with `first(max_items + 1)`; a lazy one without it raises.
- `FieldStruct.register_option(name, type:, owner:)` and `FieldStruct.registered_options`: the keys an adapter or app
  reads on a field. The value is checked against `type:` at declaration.
- `:hash, of:`, a map with String keys (Symbols converted, other key classes refused); `element:` passes options to
  every value, `{}` is missing, messages name a count and never a key, and `errors.paths` names struct entries as
  `field{"key"}.child`. `FieldStruct::Introspection::MapNode` describes it to exporters.
- `Klass.partial`, a sibling class `Klass::Partial` for update bodies: every field optional, no defaults, the
  same mappings and policies, `json_omit :unset`; cross-field validators and methods on `Klass` don't carry over.
- `json_omit :unset`, a class setting: `as_json` and `to_json` leave out a field the caller didn't give whose value is
  `nil`. Defaults and a given `nil` are still written. The default, `:none`, writes every field as before.
- `model_name.param_key`, the same as `singular`, so `form_with model: struct, url: ...` names its fields
  `<singular>[<field>]`.

### Changed

- `to_json` writes a BigDecimal as a JSON number with every digit, at any depth; `as_json` still gives the String.
  `json: :string` on a decimal field (or `element: {json: :string}`) keeps the string in `to_json`, and a
  `Types::BigDecimal` subclass can make that its default with `json_default`.
- An option key nobody declares or registers raises at declaration, with a did-you-mean (`requird: true` used to be
  stored and ignored). A first-party adapter's key used before the adapter loads says which file to require.
- The setter and `:array` elements call built-in types without a keyword splat, which YJIT compiles better. A
  custom type, or a subclass that overrides `coerce` alone, still gets every option as keywords.

### Fixed

- `sig/manifest.yaml` names the standard libraries the signature uses (`pp`, `date`, `bigdecimal`), so the sig
  loads on its own with `rbs -r field_struct` or an RBS collection.
- `sig/`: `Types::Base.instantiate` and `Types::Union.instantiate` return `[instance, options]`, not
  `FieldStruct::Types::Symbol`.

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
