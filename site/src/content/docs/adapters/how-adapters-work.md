---
title: "How adapters work"
description: "Why the adapters are separate gems on one shared walk, why they describe the JSON, and why they refuse to approximate."
sidebar:
  badge:
    text: Unreleased
    variant: caution
  label: "How adapters work"
  order: 9
---

This page covers why the adapters look the way they do. To use one, read that adapter's page. To write one, go to [Build your own adapter](/adapters/build-your-own/).

## Why separate gems

Every adapter has its own version, changelog and release tag. Someone who wants Avro installs Avro, with no JSON Schema generator, Protobuf runtime or tracing library along for the ride, and a fix in one adapter never forces a release of another.

The base gems stay small for the same reason. `field_struct` has no JSON Schema export and no `to_json_schema` method (FS-B140), and `actionable` never loads OpenTelemetry. Only the adapters that need a third-party library, like `avro` or `google-protobuf`, depend on it. The tools adapter depends on neither `mcp` nor `ruby_llm`. Each one is needed only by its own `require`, and a missing one raises an error that names the gem to add.

The cost is more gems to install and keep in step. We think it is worth it, and the version ranges in each adapter's gemspec do the keeping in step.

## Why one walk

JSON Schema, Avro and Protobuf all begin the same way: go through the fields, find each one's external name, and see what kind of type it has. If every adapter read a struct's internals on its own, each would lean on private details and each would hit its own bugs in the same spots.

[`FieldStruct::Introspection`](/adapters/introspection/) is that first step, written once and living in `field_struct`. It reports declarations and nothing more. Nullability, defaults and type mapping differ by format, so it decides none of them. Avro writes `["null", T]` for an optional field, JSON Schema writes `"type": ["T", "null"]`, and Protobuf writes `optional`. Keeping the walk neutral lets each adapter be right about its own format.

One side effect: anyone can write an adapter. Third-party exporters get the same walk as the first-party ones, and core has nothing else aimed at exporters.

## Why they describe the JSON

When a format forces a choice between Ruby behaviours, the adapters describe what a struct writes, not what it accepts. Setters are permissive - they take `'42'` for an integer and a Hash for a nested struct - while `to_json` is canonical. The JSON Schema adapter describes that canonical form (JS-I1), so the `to_json` of every valid instance validates and the schema stays short enough to read.

It also explains why an optional field is nullable in JSON Schema: `to_json` writes `null` for each unset field. And a field with a default isn't `required`, because the default fills in a missing key.

## Why never approximate

When an adapter can't state a rule exactly, it raises or leaves the rule out. It never rounds, truncates or guesses.

- Avro raises on a time with nanoseconds under a micros schema (AV-I1). Rounding would alter the value, and a silently altered value is the worst failure a data format can have.
- Avro compares a pair of schemas before reading old bytes, because the `avro` gem would decode a decimal at the wrong scale into a wrong number without any error.
- Protobuf never numbers fields by declaration order, since reordering a class would then change the wire format silently (PB-I1). It refuses a union too, because a `oneof` needs a number per member and there is no way to declare one yet.
- JSON Schema omits `in:` on dates and `round:` on decimals, since it can't express them. `pattern_for` returns `nil` unless its translation is exact (JS-I2), because a wrong pattern would make a validator in another language reject values the struct accepts. It also refuses a pattern that a backtracking JavaScript engine could take exponential time on, even though Ruby itself is safe, since those schemas get read by validators that handle untrusted input (JS-I3).

Each case follows one rule: a clear error or a documented gap beats a value that is quietly wrong. The cost is that some structs can't be exported until you make a choice, like giving every field a number.

## Why they don't change your classes

Requiring an adapter adds a module and nothing more. After `require 'field_struct/avro'` your classes have no `to_avro` method. When you want `Hut.to_avro_schema`, include the adapter's `Methods` module in the class. Everything also works as a module function, `FieldStruct::Avro.schema(Hut)`, with the class left alone (AV-I8).

OpenTelemetry is the one exception. Tracing has to wrap `Action.run`, so requiring `actionable/otel` switches it on. It touches core in exactly two places, and results, history and exceptions come out unchanged (OT-I3, OT-I4).

## What an adapter may rely on

An adapter, whether first-party or yours, may rely on this public API, each item with a promise attached:

- the `Introspection` members and the frozen shape of their nodes
- the `Field` readers, the `Metadata#serialization` mapping, the type-class readers and the `ruby_type` table (FS-B155 to FS-B164)
- the identity guarantees, so an adapter can cache per class and know exactly when to rebuild

It may not rely on private methods, on `Types::Base` offering an export hook (core defines none, so an adapter asks with `respond_to?`), or on a pass-through option being validated. Options like `avro:` and `proto:` sit in `options` verbatim, and what they mean belongs to the adapter that reads them.

## Where we are not sure

The shared contract says an array of unions records only the union class, so you can't reach the members of that union from the array node. It is documented, and the specs give no reason beyond how arrays store their element type. If you run into it, override the array field with the adapter's own option.

## See also

- [Introspection reference](/adapters/introspection/)
- [Build your own adapter](/adapters/build-your-own/)
- [Adapters overview](/adapters/)
