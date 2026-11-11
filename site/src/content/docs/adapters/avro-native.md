---
title: "Avro native encoder"
description: "An optional Rust encoder for field_struct-avro: the same Avro bytes, written about 2.6 times faster, with the pure Ruby path as the fallback."
sidebar:
  badge:
    text: Unreleased
    variant: caution
  label: "Avro native"
  order: 3.5
---

`field_struct-avro-native` is an optional speed-up for [`FieldStruct::Avro.encode`](/adapters/avro/). It writes the same bytes as the pure Ruby path, from Rust, and anything it isn't sure about goes back to Ruby. `field_struct-avro` never depends on it.

```ruby
gem 'field_struct-avro-native'
```

```ruby
require 'field_struct/avro/native'
```

Without that `require`, nothing changes.

## What it speeds up

`encode` builds a datum with `to_datum`, then hands it to the `avro` gem's binary writer. The writer is most of the cost. It validates the whole datum first, then writes varints one byte at a time. The native gem replaces only that last step. It compiles each writer schema once into an encoding plan and walks the datum in Rust into a single buffer.

The numbers below are in `benchmarks/BASELINE.md` ("Native avro encoder"), measured on Ruby 4.0.7 with YJIT, the Order-like struct from `field_struct-avro`'s benchmark:

| Workload | Pure Ruby | Native | Speedup |
|---|---:|---:|---:|
| `encode`, 1 order | 23,476 per second | 61,468 per second | 2.62x |
| `encode`, 1000 orders (per call) | 23.2 | 61.6 | 2.66x |
| Objects allocated per order | 417 | 155 | |

The write step alone goes from 26.4 us to 1.9 us, about 14 times faster. What remains is mostly `to_datum`, at about 12.6 us. Reading is untouched: `decode` stays pure Ruby.

## Turn it on

Require it once, after `field_struct/avro`. `FieldStruct::Avro::Native.enabled?` tells you whether the encoder is in place.

```ruby run
require 'field_struct/avro'

defined?(FieldStruct::Avro::Native)   # => nil
```

```ruby
require 'field_struct/avro/native'

FieldStruct::Avro::Native.enabled?    # => true
```

The require prepends a small module to `FieldStruct::Avro`. From then on, the calls you already make go through the plan:

```ruby
module Signals
  class Dispatch < FieldStruct::Base
    required :id, :uuid
    required :lamp, :symbol, enum: %i[fixed flashing]
    required :swell, :big_decimal, round: 2
    required :sent, :time, zone: 'America/Denver'
    optional :channels, :array, of: :string
  end
end

dispatch = Signals::Dispatch.new(id: '3c5e7a10-92b4-4f6d-8e21-0a7d5b9c1e44', lamp: :flashing, swell: '2.75',
                                 sent: '2026-07-01T08:00:00', channels: %w[ch-16 ch-9])

bytes = FieldStruct::Avro.encode(dispatch)    # the same bytes as without the require
FieldStruct::Avro.decode(Signals::Dispatch, bytes) == dispatch   # => true
```

Output is byte for byte what the pure path writes, for every datum the pure path accepts. `FieldStruct::Avro::Native.encode(schema, datum)` is the lower-level call. It takes a parsed `Avro::Schema` and a datum, and returns the bytes, or `nil` when it leaves the datum to Ruby.

## What falls back to pure Ruby

The encoder never raises an error of its own. When it isn't sure about a datum it returns `nil`, and the pure path then writes it or raises exactly the error the [Avro page](/adapters/avro/) describes. It falls back for:

- a value of a class it doesn't expect, such as an Integer in a `double` field or a `DateTime` in a `date` field
- a value out of range: an integer past `int` or `long`, a decimal past its precision or scale, a time past `long`
- a String in an encoding other than UTF-8 (7-bit US-ASCII and binary are fine)
- a record datum that isn't exactly what `to_datum` builds
- a union member it can't rule in or out the way the `avro` gem would
- a schema shape it doesn't cover: `fixed`, and logical types other than `decimal` (on bytes), `date`, `timestamp-millis`, `timestamp-micros`, `timestamp-nanos` and the identity ones like `uuid`

It also copies two quirks of `avro` 1.12 by falling back. A decimal zero at scale 0 raises "Rounding necessary", and a map with a key that isn't valid UTF-8 raises when the map sits inside a union.

A fallback costs the pure path plus the failed attempt. A schema it can't cover is remembered, so that check isn't repeated for each call.

The plan lives on the parsed schema, so it follows the adapter's cache. A rebuilt entry, or `FieldStruct::Avro.clear_cache`, means a new schema and a new plan.

## Install

Today `gem install field_struct-avro-native` compiles the Rust extension on your machine. You need a stable Rust toolchain and a C compiler.

Precompiled gems are planned, so that installing needs no Rust. They will be built with `rb-sys` cross-compilation for `x86_64-linux`, `aarch64-linux` and `arm64-darwin`, and every other platform keeps the source gem as its fallback. The release workflow builds and smoke-tests them, but nothing has been published yet.

## Limits

- Only `encode` is faster. `decode`, `schema`, `to_datum` and `from_datum` are the same code as before.
- Anything but an exact `String`, `Hash`, `Array`, `Time`, `Date` or `BigDecimal` falls back, subclasses included.
- Ruby 3.3 or newer, and the same `avro` gem (1.12) that `field_struct-avro` uses.

## See also

- [Avro](/adapters/avro/)
- [How adapters work](/adapters/how-adapters-work/)
