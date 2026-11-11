# field_struct-avro-native

An optional Rust encoder for [field_struct-avro](../field_struct-avro). It writes the same Avro bytes as the
pure-Ruby path, about 2.6x faster end to end on an Order-like struct.

<!-- doctest -->
```ruby
require 'field_struct/avro'

class Beacon < FieldStruct::Base
  required :id, :integer
  required :tower, :string
end

pure = FieldStruct::Avro.encode(Beacon.new(id: 7, tower: 'north'))

require 'field_struct/avro/native'

FieldStruct::Avro::Native.enabled? # => true
FieldStruct::Avro.encode(Beacon.new(id: 7, tower: 'north')) == pure # => true
```

Without the `require`, nothing changes. field_struct-avro doesn't depend on this gem.

## What it does

`FieldStruct::Avro.encode` builds a datum with `to_datum` and hands it to the avro gem's binary writer. That
writer is most of the cost: it validates the whole datum, then writes varints a byte at a time. This gem replaces
only that last step. It compiles each parsed writer schema once into an encoding plan, keeps it on the schema
object (so it follows the adapter's cache: a rebuilt or cleared entry gets a new schema and a new plan), and
walks the datum in Rust into one buffer.

The contract is byte-for-byte identical output. When the plan is not sure about a datum, it doesn't raise.
It hands the datum to the pure path, which then writes it or raises exactly the error the field_struct-avro
spec describes. It falls back for:

- a value of a class the plan doesn't expect, like an Integer in a `double` field or a DateTime in a `date` field
- a value out of range: an integer past `int`/`long`, a decimal past its precision or scale, a time past `long`
- a String in an encoding other than UTF-8, or 7-bit US-ASCII/binary
- a record datum that isn't exactly what `to_datum` builds (String keys, one per field, in field order)
- a union member it can't rule in or out the way the avro gem would
- schema shapes it doesn't cover: `fixed`, logical types other than `decimal` (on bytes), `date`,
  `timestamp-millis/micros/nanos` and the identity ones like `uuid`

Two avro gem 1.12 quirks the plan copies by falling back: a decimal zero at scale 0 raises "Rounding
necessary", and a map with a key that is not valid UTF-8 raises inside a union.

## Building

You need Rust (stable) and a C toolchain. From this directory:

```sh
bundle install
bundle exec rake compile   # builds lib/field_struct/avro/field_struct_avro_native.bundle
bundle exec rake           # compile, specs, field_struct-avro's suite with native, rubocop, clippy, cargo test
```

The Ruby-free kernels (zigzag varints, decimal bytes) live in their own crate, `ext/field_struct_avro_kernel`,
so `cargo test` runs without linking libruby.

## Release builds

`bundle exec rake native gem` builds a platform gem for the machine you are on. The other platforms are built in
containers: `bundle exec rb-sys-dock --platform aarch64-linux --ruby-versions 3.3,3.4,4.0 --build` (needs Docker; the
gem lands in `pkg/`). The tag workflow, `field_struct-avro-native-release.yml`, does this for every platform plus the
source gem, smoke-tests each, and uploads them as artifacts. It never publishes.
`support/smoke_install.sh <gem>` installs a built gem into a throwaway `GEM_HOME` and runs an encode.

## Proof

- `spec/field_struct/avro/native/datum_fuzz_spec.rb` - 9,000 random schema/datum pairs per run, edges and wrong
  shapes included: whenever the plan writes, the pure path writes the same bytes, and it must take most datums
  and leave both good and bad ones to the pure path
- `struct_differential_spec.rb` - 3,000 random structs over every field type the adapter maps, at each timestamp
  precision: same bytes, and they decode and re-encode to the same bytes
- `fallback_spec.rb` - each error in the adapter spec (AV-B21, B33, B34, B35) comes out the same with native on
- `rake upstream` - field_struct-avro's whole suite with `FIELD_STRUCT_AVRO_NATIVE=1`

## Numbers

Ruby 4.0.7 with YJIT on an M-series Mac, `adapters/field_struct-avro/benchmarks/perf.rb` with and without
`-rfield_struct/avro/native`, two runs each:

| workload | pure | native | speedup |
|---|---:|---:|---:|
| encode, 1 order | 23,476 i/s (42.6 us) | 61,468 i/s (16.3 us) | 2.6x |
| encode, 1000 orders | 23.2 i/s (43.2 us/order) | 61.6 i/s (16.2 us/order) | 2.7x |
| allocations per order | 417 | 155 | |

The write step alone goes from 26.4 us to 1.9 us. What is left is `to_datum` (12.6 us), so the next step, if
we want one, is a plan that reads the struct directly instead of the datum Hash.

## Not yet

- Published precompiled platform gems. The release workflow builds them (x86_64-linux, aarch64-linux, arm64-darwin)
  but nothing is published yet, so installing compiles from source.
- `decode` stays pure Ruby. The avro gem's decimal reader is the hot spot there, ceiling about 1.6x.
