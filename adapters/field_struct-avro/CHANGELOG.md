# Changelog

## [Unreleased]

### Added

- Requiring the adapter registers `avro:` with `FieldStruct.register_option`, so field_struct accepts the key and
  refuses a non-Hash value when the field is declared.
- A required field declared `nullable: true` is the union `["null", T]` with no default, so a nil encodes and a reader
  still needs the field; with a default it is `[T, "null"]` plus that default.
- `:hash, of:` is an Avro `map` with nullable values; values are written and read like array items, and struct values
  become records.

### Fixed

- `avro:` refuses a key the adapter doesn't read (`avro: {scal: 2}` raises with "did you mean scale:?"), where it used
  to be ignored; it takes `type:`, `scale:`, `precision:`, `timestamp:`, `enum:` and `enum_default:`.

### Changed

- Faster encoding and decoding of plain scalar fields; error messages are unchanged.

## 1.0.0.pre1

- First release: Apache Avro for field_struct classes.
  - `FieldStruct::Avro.schema`: a record schema from a struct (lossless mapping: `long`, `decimal`, `timestamp-*`, enums, nested
    and recursive records, unions), parsed by the avro gem so a bad `avro:` option fails at boot.
  - `to_datum`, `from_datum`, `encode`, `decode`: datums and the Avro binary encoding of one value, with time precision,
    `zone:` and `:value` handling and errors that never echo a sensitive field.
  - `decode(writer_schema:)`: reads bytes written with an older schema after a resolution check that refuses the changes the
    avro gem would silently misread (decimal scale, timestamp precision, optional to required); absent fields take the
    field_struct default.
  - Caches for schemas, property lists and checked writer schemas, with `clear_cache`; the opt-in `Methods` mixin.
