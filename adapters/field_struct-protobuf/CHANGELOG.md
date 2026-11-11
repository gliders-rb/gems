# Changelog

## 1.0.0.pre1

- Preview release: Protocol Buffers for field_struct classes, with no `protoc` step.
  - `FieldStruct::Protobuf.proto` and `file_descriptor`: the `.proto` text and descriptor of a class (proto3, explicit presence for
    scalars, one file per class), equivalent to what `protoc` compiles from the text.
  - `message_class`, `to_message`, `from_message`, `encode`, `decode`: runtime messages registered with `google-protobuf`, binary
    round trips with `Timestamp` and `Value` support, and `zone:` restored on decode.
  - Field numbers are declared with `proto: {number: n}` and never inferred; anything without an exact mapping raises
    `ArgumentError` naming the class and field.
