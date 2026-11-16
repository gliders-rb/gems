# Changelog

## [Unreleased]

### Added

- Requiring the adapter registers `proto:` with `FieldStruct.register_option`, so field_struct accepts the key and
  refuses a non-Hash value when the field is declared.
- `:hash, of: X` maps to `map<string, X>`, encoded and decoded with String keys. Array and map values are refused,
  since proto3 has no repeated or map values, and a `nil` value is refused on encode.

### Fixed

- Refusals say what to do: an unusable field number names the allowed range, and a union says to split it into one
  field per member type or declare it `:value`.
- `proto:` refuses a key other than `number:`, with a did-you-mean when the key is close.

## 1.0.0.pre1

- Preview release: Protocol Buffers for field_struct classes, with no `protoc` step.
  - `FieldStruct::Protobuf.proto` and `file_descriptor`: the `.proto` text and descriptor of a class (proto3, explicit presence for
    scalars, one file per class), equivalent to what `protoc` compiles from the text.
  - `message_class`, `to_message`, `from_message`, `encode`, `decode`: runtime messages registered with `google-protobuf`, binary
    round trips with `Timestamp` and `Value` support, and `zone:` restored on decode.
  - Field numbers are declared with `proto: {number: n}` and never inferred; anything without an exact mapping raises
    `ArgumentError` naming the class and field.
