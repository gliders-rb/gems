# field_struct-avro

Apache Avro for [field_struct](../../gems/field_struct) classes. Generate a record schema from a struct, turn
instances into Avro datums (the Hash the `avro` gem reads and writes) and back, and read and write the Avro binary
encoding, including bytes written with an older schema.

Nothing is lost on the way: integers are `long`, decimals with a scale are Avro `decimal`, times keep their
sub-second digits and symbols with an `enum:` are Avro enums. Where Avro can't hold a value exactly, you get an error,
never a rounded value. It does not validate (`format:`, `in:`), and it handles one datum at a time: no container
files, no schema registry, no Avro JSON.

## Install

```ruby
gem 'field_struct-avro'
```

```ruby
require 'field_struct/avro'
```

## Quick start

<!-- doctest -->
```ruby
require 'field_struct/avro'

module Harbor
  class Beacon < FieldStruct::Base
    include FieldStruct::Avro::Methods # opt in to Beacon.to_avro_schema, #to_avro and Beacon.from_avro

    required :id,    :uuid
    required :reach, :big_decimal, round: 2
    required :lit, :time, zone: 'America/Denver'
    required :tower, :symbol, enum: %i[new used]
    optional :codes,  :array, of: :string
  end
end

schema = FieldStruct::Avro.schema(Harbor::Beacon) # the same as Harbor::Beacon.to_avro_schema
schema['name']                                   # => "Beacon"
schema['namespace']                              # => "Harbor"
schema['fields'][1]['type']                      # => {"type"=>"bytes", "logicalType"=>"decimal", "precision"=>38, "scale"=>2}
schema['fields'][3]['type']                      # => {"type"=>"enum", "name"=>"Beacon_tower", "symbols"=>["new", "used"]}
schema['fields'][4]['type']                      # => ["null", {"type"=>"array", "items"=>["null", "string"]}]

beacon = Harbor::Beacon.new(id: '8b1f4d4a-0d0e-4b29-9f4d-6a1b3d3c9f00', reach: '19.90',
                         lit: '2026-07-01T08:00:00', tower: :new, codes: %w[fiction])
bytes = beacon.to_avro                             # the same as FieldStruct::Avro.encode(beacon)
Harbor::Beacon.from_avro(bytes) == beacon           # => true
FieldStruct::Avro.decode(Harbor::Beacon, bytes).lit.utc_offset # => -21600
```

`schema` returns a fresh copy every time, so changing the result changes nothing else. `serialization:` picks the
`serialize` mapping whose names become Avro field names (default `:avro`); `timestamp:` is `:micros` (default),
`:nanos` or `:millis`.

## What the schema says

| Field type | Avro |
|---|---|
| `:integer` | `long`, never `int` |
| `:float` | `double` |
| `:string`, `:email`, `:url`, `:value` | `string` (`:value` holds JSON text) |
| `:uuid` | `string` with `logicalType` `uuid` |
| `:binary` | `bytes` |
| `:big_decimal` | `decimal` with the field's scale (`round:` or `avro: {scale:}`); a `string` when there is none |
| `:date` | `int` with `logicalType` `date` |
| `:time`, `:datetime` | `long` with `timestamp-micros`, `-nanos` or `-millis` |
| `:symbol` with `enum:` | a named Avro `enum`; otherwise `string` |
| arrays | `array`, items always nullable (field_struct accepts nil elements) |
| nested structs | a named `record`, referenced by full name after its first use |

An optional field is `["null", T]` with a `null` default; a field with a usable default is not nullable and carries
that default. Defaults Avro can't write (a date, a decimal, a lambda) are left out of the schema and applied by
field_struct when the value is read.

<!-- doctest -->
```ruby
class Reading < FieldStruct::Base
  required :value, :big_decimal
  required :count, :integer, default: 0
  optional :note, :string, desc: 'free text'
end

fields = FieldStruct::Avro.schema(Reading)['fields']
fields[0]  # => {"name"=>"value", "type"=>"string"}
fields[1]  # => {"name"=>"count", "type"=>"long", "default"=>0}
fields[2]  # => {"name"=>"note", "doc"=>"free text", "type"=>["null", "string"], "default"=>nil}
```

## Field options: `avro:`

A field's `avro:` option is a Hash. `type:` replaces the whole mapping with an Avro type you write; `timestamp:`,
`precision:`, `scale:`, `enum: false` and `enum_default:` tune the generated one. On array and union fields, everything
but `type:` also applies to the items.

<!-- doctest -->
```ruby
class Dispatch < FieldStruct::Base
  required :fee,   :big_decimal, avro: { scale: 2, precision: 12 }
  required :seen,  :time, avro: { timestamp: :millis }
  required :level, :symbol, enum: %i[low high], avro: { enum_default: :low }
  required :ref,   :string, avro: { type: { 'type' => 'string', 'x-origin' => 'crm' } }
end

types = FieldStruct::Avro.schema(Dispatch)['fields'].to_h { |f| [f['name'], f['type']] }
types['fee']   # => {"type"=>"bytes", "logicalType"=>"decimal", "precision"=>12, "scale"=>2}
types['seen']  # => {"type"=>"long", "logicalType"=>"timestamp-millis"}
types['level'] # => {"type"=>"enum", "name"=>"Dispatch_level", "symbols"=>["low", "high"], "default"=>"low"}
types['ref']   # => {"type"=>"string", "x-origin"=>"crm"}
```

## Datums and bytes

`to_datum` and `from_datum` stop at the Hash the `avro` gem reads and writes; `encode` and `decode` go to and from
binary (one datum, no header).

<!-- doctest -->
```ruby
class Pair < FieldStruct::Base
  required :first_name, :string
  required :updated, :time
  serialize :avro, first_name: 'firstName'
end

pair = Pair.new(first_name: 'Ada', updated: Time.utc(2026, 10, 25, 21, 55, 12))
datum = FieldStruct::Avro.to_datum(pair)
datum.keys                                    # => ["firstName", "updated"]
FieldStruct::Avro.from_datum(Pair, datum) == pair # => true

late = Pair.new(first_name: 'Ada', updated: Time.utc(2026, 10, 25, 21, 55, 12, Rational(123_456_789, 1000)))
begin
  FieldStruct::Avro.encode(late)
rescue ArgumentError => e
  e.message # => "FieldStruct::Avro: Pair#updated is 2026-10-25T21:55:12.123456789Z, which has more precision than timestamp-micros; round it, or use timestamp: :nanos"
end
FieldStruct::Avro.decode(Pair, FieldStruct::Avro.encode(late, timestamp: :nanos), timestamp: :nanos) == late # => true
```

Errors are `ArgumentError`s that name the class and field (`Pair#updated`). They never echo the value of a
`sensitive: true` field. Bytes that can't be read at all raise one `ArgumentError` with the avro gem's error as the
`cause`. A few errors of the `avro` gem itself pass through as raised, and may quote the value they couldn't write: a
decimal past its precision, an integer past 64 bits, an `avro: {type:}` override the value doesn't fit.

## Reading bytes written with an older schema

Pass the schema the bytes were written with as `writer_schema:`: a Hash, a JSON String or a parsed `Avro::Schema`.
Avro matches record names, so the older schema carries the name of the class that reads it. Fields the writer lacked
take the field_struct default, even one Avro can't express.

<!-- doctest -->
```ruby
module V1
  class Account < FieldStruct::Base
    required :id, :integer
  end
end

module V2
  class Account < FieldStruct::Base
    required :id, :integer
    optional :nickname, :string
    required :opened, :date, default: Date.new(2026, 1, 1)
  end
end

bytes = FieldStruct::Avro.encode(V1::Account.new(id: 7))
old = FieldStruct::Avro.schema(V1::Account).merge('namespace' => 'V2')
account = FieldStruct::Avro.decode(V2::Account, bytes, writer_schema: old)
[account.id, account.nickname, account.opened] # => [7, nil, Date.new(2026, 1, 1)]
```

The `avro` gem pairs fields by their base type only, so a decimal read at another scale, or a timestamp at another
precision, would decode to a wrong value without a word. Before reading, the pair of schemas is checked and the decode
is refused with every problem listed:

<!-- doctest -->
```ruby
module Before
  class Lamp < FieldStruct::Base
    required :reach, :big_decimal, round: 2
  end
end

module After
  class Lamp < FieldStruct::Base
    required :reach, :big_decimal, round: 3
  end
end

bytes = FieldStruct::Avro.encode(Before::Lamp.new(reach: '1.25'))
old = FieldStruct::Avro.schema(Before::Lamp).merge('namespace' => 'After')
begin
  FieldStruct::Avro.decode(After::Lamp, bytes, writer_schema: old)
rescue ArgumentError => e
  e.message # => "FieldStruct::Avro can't read these bytes: reach: written as decimal (scale 2), read as decimal (scale 3). The avro gem would decode them as the wrong value, or fail; this is not a compatible schema change"
end
```

A symbol the reader's enum lacks raises, naming the field, unless the field says what to read instead with
`avro: {enum_default:}`.

## Caching

Schemas, parsed schemas, field lists and checked writer schemas are cached per class, so `encode` and `decode` don't
rebuild anything. Adding or redeclaring a field, declaring a `serialize` later or naming an anonymous struct is noticed
on the next call. Changing a field's options in place (the `avro:` Hash, the `enum:` Array) is not: redeclare the
field. The cache keeps classes alive, so call `FieldStruct::Avro.clear_cache` when code reloads.

## Reference

| Call | Returns |
|---|---|
| `FieldStruct::Avro.schema(klass, serialization:, timestamp:)` | the record schema, a Hash with String keys |
| `FieldStruct::Avro.to_datum(struct, serialization:, timestamp:)` | the datum Hash |
| `FieldStruct::Avro.from_datum(klass, datum, serialization:)` | a struct |
| `FieldStruct::Avro.encode(struct, serialization:, timestamp:)` | Avro binary |
| `FieldStruct::Avro.decode(klass, bytes, writer_schema:, serialization:, timestamp:)` | a struct |
| `FieldStruct::Avro.clear_cache` | `nil` |
| `FieldStruct::Avro::Methods` | opt-in `to_avro_schema`, `#to_avro`, `from_avro` |

Needs Ruby 3.3 or newer. MIT licensed.
