---
title: "Avro"
description: "Write structs as Avro binary, read dispatches saved with an older class, and get an error where a value would have been rounded."
sidebar:
  badge:
    text: Unreleased
    variant: caution
  label: "Avro"
  order: 3
---

`field_struct-avro` maps a struct to an Avro record schema, an instance to a datum or to Avro binary, and bytes back to an instance. That includes bytes an older version of the class wrote.

```ruby
gem 'field_struct-avro'
```

```ruby
require 'field_struct/avro'
```

The unit of work is one datum. Container files, a schema registry and Avro JSON are all out of scope, and so is validation (`format:`, `in:`), which stays with the struct.

If Avro has no exact way to hold a value, you get an `ArgumentError` instead of a rounded number.

## The schema of a struct

```ruby run
require 'field_struct/avro'

module Signals
  class Dispatch < FieldStruct::Base
    required :id, :uuid
    required :lamp, :symbol, enum: %i[fixed flashing]
    required :swell, :big_decimal, round: 2
    required :sent, :time, zone: 'America/Denver'
    optional :channels, :array, of: :string
  end
end

schema = FieldStruct::Avro.schema(Signals::Dispatch)
schema['name']                  # => "Dispatch"
schema['namespace']             # => "Signals"
schema['fields'].map { |f| f['name'] }   # => ["id", "lamp", "swell", "sent", "channels"]
schema['fields'][1]['type']     # => {"type"=>"enum", "name"=>"Dispatch_lamp", "symbols"=>["fixed", "flashing"]}
schema['fields'][2]['type']     # => {"type"=>"bytes", "logicalType"=>"decimal", "precision"=>38, "scale"=>2}
schema['fields'][4]['type']     # => ["null", {"type"=>"array", "items"=>["null", "string"]}]
```

The mapping holds on to as much as Avro allows. Integers become `long`, never `int`. A decimal that has a scale (from `round:`) becomes an Avro `decimal`, and times keep every sub-second digit. A symbol with `enum:` turns into an Avro `enum`. Optional fields are unions with `null`. Array items are always nullable too, because a struct lets `nil` elements through.

| Field type | Avro |
|---|---|
| `:integer` | `long` |
| `:float` | `double` |
| `:string`, `:email`, `:url`, `:value` | `string` (`:value` holds JSON text) |
| `:uuid` | `string` with `logicalType` `uuid` |
| `:binary` | `bytes` |
| `:big_decimal` | `decimal` with the field's scale, or `string` with no scale |
| `:date` | `int` with `logicalType` `date` |
| `:time`, `:datetime` | `long` with `timestamp-micros`, `-nanos` or `-millis` |
| `:symbol` with `enum:` | a named `enum`; otherwise `string` |
| arrays | `array`, items nullable |
| nested structs | a named `record`, referenced by full name after its first use |

A field with a usable default is not nullable, and the schema carries that default. A default Avro can't write (a date, a decimal, a lambda) stays out of the schema, and the struct fills it in on read.

Each `schema` call gives you a fresh copy. For `Signals::Dispatch.to_avro_schema`, `#to_avro` and `Signals::Dispatch.from_avro`, include `FieldStruct::Avro::Methods`.

## Use case: send a signal, read it back

Say a lighthouse sends a dispatch to the harbor office. `encode` writes one datum as Avro binary, and `decode` reads it into a struct of whichever class you name.

```ruby run
dispatch = Signals::Dispatch.new(id: '3c5e7a10-92b4-4f6d-8e21-0a7d5b9c1e44', lamp: :flashing, swell: '2.75',
                                 sent: '2026-07-01T08:00:00', channels: %w[ch-16 ch-9])

bytes = FieldStruct::Avro.encode(dispatch)
bytes.encoding                                # => #<Encoding:BINARY (ASCII-8BIT)>
back = FieldStruct::Avro.decode(Signals::Dispatch, bytes)
back == dispatch                              # => true
back.sent.utc_offset                          # => -21600
```

The field's `zone:` puts the offset back on the way in. When all you need is the Hash the `avro` gem reads and writes, call `to_datum` and `from_datum`.

```ruby run
datum = FieldStruct::Avro.to_datum(dispatch)
datum.keys                                                       # => ["id", "lamp", "swell", "sent", "channels"]
FieldStruct::Avro.from_datum(Signals::Dispatch, datum) == dispatch   # => true
```

## Use case: read old signals after a class changes

A dispatch logged last month predates two fields the class has since gained. Hand `decode` the schema those bytes were written with, as `writer_schema:`. A Hash, a JSON String or a parsed `Avro::Schema` all work. Avro pairs records by name, so the old schema must carry the namespace of the class doing the reading.

```ruby run
module Gen1
  class Buoy < FieldStruct::Base
    required :serial, :integer
  end
end

module Gen2
  class Buoy < FieldStruct::Base
    required :serial, :integer
    optional :callsign, :string
    required :moored, :date, default: Date.new(2026, 3, 14)
  end
end

old_bytes = FieldStruct::Avro.encode(Gen1::Buoy.new(serial: 31))
old_schema = FieldStruct::Avro.schema(Gen1::Buoy).merge('namespace' => 'Gen2')

buoy = FieldStruct::Avro.decode(Gen2::Buoy, old_bytes, writer_schema: old_schema)
[buoy.serial, buoy.callsign, buoy.moored]   # => [31, nil, Date.new(2026, 3, 14)]
```

A field the writer never had gets the struct's own default, even one Avro can't express, like a date.

## It raises rather than lose data

A time carrying nanoseconds does not fit `timestamp-micros`. Rounding would change the value, so the adapter stops and tells you what to do about it.

```ruby run
class Roster < FieldStruct::Base
  required :keeper_name, :string
  required :logged, :time
  serialize :avro, keeper_name: 'keeperName'
end

entry = Roster.new(keeper_name: 'Odd', logged: Time.utc(2026, 10, 25, 21, 55, 12, Rational(123_456_789, 1000)))

begin
  FieldStruct::Avro.encode(entry)
rescue ArgumentError => e
  e.message   # => "FieldStruct::Avro: Roster#logged is 2026-10-25T21:55:12.123456789Z, which has more precision than timestamp-micros; round it, or use timestamp: :nanos"
end

nanos = FieldStruct::Avro.encode(entry, timestamp: :nanos)
FieldStruct::Avro.decode(Roster, nanos, timestamp: :nanos) == entry   # => true
FieldStruct::Avro.to_datum(entry, timestamp: :nanos).keys             # => ["keeperName", "logged"]
```

In the datum, the `serialize :avro` mapping renamed `keeper_name` to `keeperName`. `serialization:` defaults to `:avro`.

Reading gets the same care. The `avro` gem matches fields on their base type alone, so a decimal read at a different scale would come out as a wrong number with no warning. The adapter compares the two schemas first and refuses the decode, listing every problem it found.

```ruby run
module Spring
  class Tide < FieldStruct::Base
    required :height, :big_decimal, round: 2
  end
end

module Autumn
  class Tide < FieldStruct::Base
    required :height, :big_decimal, round: 3
  end
end

logged = FieldStruct::Avro.encode(Spring::Tide.new(height: '4.25'))
written_with = FieldStruct::Avro.schema(Spring::Tide).merge('namespace' => 'Autumn')

begin
  FieldStruct::Avro.decode(Autumn::Tide, logged, writer_schema: written_with)
rescue ArgumentError => e
  e.message   # => "FieldStruct::Avro can't read these bytes: height: written as decimal (scale 2), read as decimal (scale 3). The avro gem would decode them as the wrong value, or fail; this is not a compatible schema change"
end
```

Every error is an `ArgumentError` naming the class and field, and none of them echoes the value of a `sensitive: true` field. Bytes that can't be read at all raise a single `ArgumentError`, with the `avro` gem's own error as its `cause`.

## Options

A field's `avro:` option is a Hash. With `type:` you replace the whole mapping by an Avro type of your own, and the other keys adjust the generated one. On array and union fields, every key except `type:` applies to the items.

| Key | Meaning |
|---|---|
| `type:` | an Avro type (Hash or String) used as is |
| `timestamp:` | `:micros`, `:nanos` or `:millis` for this field |
| `precision:`, `scale:` | the decimal's precision and scale |
| `enum: false` | write a symbol field as `string` |
| `enum_default:` | the symbol to read when the writer used one the reader lacks |

```ruby run
class Reading < FieldStruct::Base
  required :depth, :big_decimal, avro: { scale: 3, precision: 10 }
  required :taken, :time, avro: { timestamp: :millis }
  required :state, :symbol, enum: %i[calm rough], avro: { enum_default: :calm }
  required :station, :string, avro: { type: { 'type' => 'string', 'x-origin' => 'gauge' } }
end

types = FieldStruct::Avro.schema(Reading)['fields'].to_h { |f| [f['name'], f['type']] }
types['depth']    # => {"type"=>"bytes", "logicalType"=>"decimal", "precision"=>10, "scale"=>3}
types['taken']    # => {"type"=>"long", "logicalType"=>"timestamp-millis"}
types['state']    # => {"type"=>"enum", "name"=>"Reading_state", "symbols"=>["calm", "rough"], "default"=>"calm"}
types['station']  # => {"type"=>"string", "x-origin"=>"gauge"}
```

Every module function accepts `serialization:`, and the ones that write or read times accept `timestamp:` as well.

| Call | Returns |
|---|---|
| `schema(klass, serialization:, timestamp:)` | the record schema, a Hash with String keys |
| `to_datum(struct, serialization:, timestamp:)` | the datum Hash |
| `from_datum(klass, datum, serialization:)` | a struct |
| `encode(struct, serialization:, timestamp:)` | Avro binary |
| `decode(klass, bytes, writer_schema:, serialization:, timestamp:)` | a struct |
| `clear_cache` | `nil` |

## Limits

- When the writer used a symbol that the reader's `enum:` lacks, the read raises and names the field, unless that field sets `avro: {enum_default:}`.
- A handful of errors come straight from the `avro` gem and may quote the value: a decimal past its precision, an integer past 64 bits, or a value that does not fit an `avro: {type:}` override.
- Schemas are cached per class. The cache sees a new or redeclared field, but not an `avro:` Hash or `enum:` Array edited in place, so redeclare the field. Use `clear_cache` when code reloads.

## See also

- [Introspection reference](/adapters/introspection/)
- [How adapters work](/adapters/how-adapters-work/)
- [Dates, times and zones](/reference/field-struct/dates-and-times/)
