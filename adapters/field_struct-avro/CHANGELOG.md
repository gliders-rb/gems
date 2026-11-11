# Changelog

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
