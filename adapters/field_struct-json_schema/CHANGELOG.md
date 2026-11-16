# Changelog

## [Unreleased]

### Changed

- `:big_decimal` maps to `number`, since field_struct's `to_json` now writes decimals as JSON numbers. A field
  declared `json: :string` keeps the string form.

### Added

- `generate(klass, freeze: true)` (and `to_json_schema(freeze: true)`) returns the cached schema itself, deep-frozen,
  instead of a fresh copy, for callers that only read it.
- `generate(klass, decimals: :string)` describes every decimal as the string `as_json` writes, for callers that send
  `as_json`. The default, `decimals: :to_json`, follows `to_json`.
- Requiring the adapter registers `json_schema:` with `FieldStruct.register_option`, so field_struct accepts the key and
  refuses a value other than a Hash, `true` or `false` when the field is declared.
- `length:` maps to `minLength` and `maxLength` (an exclusive end gives one less, and `element:` options map inside
  `items`). A `:binary` field gets only `maxLength`, since it counts bytes and JSON Schema counts characters.
- A required field declared `nullable: true` stays in `required` and also accepts `null`.
- `:hash, of:` maps to an object with the nullable value schema under `additionalProperties`.

## 1.0.0.pre1

- First release: JSON Schema (draft 2020-12) generation for field_struct classes, `FieldStruct::JSONSchema.generate`, the opt-in
  `Methods`, and `pattern_for`, the exact-or-nil Regexp to ECMA-262 translator with its ReDoS analysis, checked against Node.
