# frozen_string_literal: true

RSpec.describe 'FieldStruct::Avro datums' do
  let(:avro) { FieldStruct::Avro }

  def round_trip(instance, **options)
    avro.decode(instance.class, avro.encode(instance, **options), **options)
  end

  describe 'to_datum scalars (AV-B19, AV-B20)' do
    it 'AV-B19: keys the datum by Avro names in declaration order, with nil at every depth' do
      k = define_struct('D1') do
        required :first_name, :string
        optional :note, :string
        serialize :avro, first_name: 'firstName'
      end
      datum = avro.to_datum(k.new(first_name: 'Ada'))
      expect(datum).to eq('firstName' => 'Ada', 'note' => nil)
      expect(datum.keys).to eq(%w[firstName note])
    end

    it 'AV-B20: converts decimals, times, symbols and passes the rest' do
      k = define_struct('D2') do
        required :reach, :big_decimal, round: 2
        required :rate, :big_decimal
        required :seen, :time
        required :stamp, :datetime
        required :kind, :symbol
        required :day, :date
        required :n, :integer
        required :bin, :binary
      end
      datum = avro.to_datum(k.new(reach: '1.5', rate: '0.333333333333333333333', seen: '2026-07-01T08:00:00Z',
                                  stamp: '2026-07-01T08:00:00Z', kind: :a, day: '2026-01-02', n: 3, bin: "\x00\x01".b))
      expect(datum['reach']).to eq(BigDecimal('1.5')).and be_a(BigDecimal)
      expect(datum['rate']).to eq('0.333333333333333333333')
      expect(datum['seen']).to be_a(Time)
      expect(datum['stamp']).to be_a(Time)
      expect(datum['kind']).to eq('a')
      expect(datum['day']).to eq(Date.new(2026, 1, 2))
      expect(datum['n']).to eq(3)
      expect(datum['bin']).to eq("\x00\x01".b)
    end

    it 'AV-B20: works for an instance of an anonymous class' do
      k = Class.new(FieldStruct::Base) { required :a, :integer }
      expect(avro.to_datum(k.new(a: 1))).to eq('a' => 1)
    end
  end

  describe 'time precision (AV-B21, AV-B6)' do
    let(:pair) { define_struct('Pair') { required :updated, :time } }
    let(:nanos) { Time.utc(2026, 10, 25, 21, 55, 12, Rational(123_456_789, 1000)) }

    it 'AV-B21: refuses a time with more precision than the schema, naming the field and the value' do
      expect { avro.to_datum(pair.new(updated: nanos)) }.to raise_error(
        ArgumentError,
        'FieldStruct::Avro: Pair#updated is 2026-10-25T21:55:12.123456789Z, which has more precision than timestamp-micros; ' \
        'round it, or use timestamp: :nanos'
      )
    end

    it 'AV-B21: allows it under nanos, and micros under micros, millis under millis' do
      expect { avro.to_datum(pair.new(updated: nanos), timestamp: :nanos) }.not_to raise_error
      expect { avro.to_datum(pair.new(updated: Time.utc(2026, 1, 1, 0, 0, 0, 123_456))) }.not_to raise_error
      expect { avro.to_datum(pair.new(updated: Time.utc(2026, 1, 1, 0, 0, 0, 123_456)), timestamp: :millis) }
        .to raise_error(ArgumentError, /more precision than timestamp-millis/)
    end

    it 'AV-B21: hides the digits of a sensitive time' do
      k = define_struct('Secretive') { required :at, :time, sensitive: true }
      expect { avro.to_datum(k.new(at: nanos)) }.to raise_error(
        ArgumentError, 'FieldStruct::Avro: Secretive#at is a sensitive time, which has more precision than timestamp-micros; ' \
                       'round it, or use timestamp: :nanos'
      )
    end

    it 'AV-B21: hides the digits under a sensitive struct field and names the path through anonymous structs' do
      inner = Class.new(FieldStruct::Base) { required :at, :time }
      k = define_struct('NoteMast') { required :inner, inner, sensitive: true }
      expect { avro.to_datum(k.new(inner: { at: nanos })) }.to raise_error(
        ArgumentError, /\AFieldStruct::Avro: NoteMast#inner\.at is a sensitive time, which has more precision/
      )
      k2 = define_struct('Mast') { required :inner, inner }
      expect do
        avro.to_datum(k2.new(inner: { at: nanos }))
      end.to raise_error(ArgumentError, /Mast#inner\.at is 2026-10-25T21:55:12\.123456789Z/)
    end

    it 'AV-B21: a named inner struct reports its own name' do
      inner = pair
      k = define_struct('Wrap') { required :pair, inner }
      expect { avro.to_datum(k.new(pair: { updated: nanos })) }.to raise_error(ArgumentError, /\AFieldStruct::Avro: Pair#updated is /)
    end

    it 'AV-B21: names the field for array elements' do
      k = define_struct('Many') { required :times, :array, of: :time }
      expect { avro.to_datum(k.new(times: [nanos])) }.to raise_error(ArgumentError, /Many#times is /)
    end

    it 'AV-B6: uses the field precision and raises the timestamp option error from to_datum' do
      k = define_struct('Fine') { required :at, :time, avro: { timestamp: :nanos } }
      expect { avro.to_datum(k.new(at: nanos)) }.not_to raise_error
      bad = define_struct('Bad') { required :at, :time, avro: { timestamp: :seconds } }
      expect { avro.to_datum(bad.new(at: Time.now.utc.round(3))) }.to raise_error(
        ArgumentError, 'FieldStruct::Avro (Bad#at) avro: {timestamp:} must be one of [:micros, :nanos, :millis], got :seconds'
      )
    end

    it 'AV-B45: lets an unrelated ArgumentError pass through unchanged' do
      boom = Class.new do
        def inspect = raise(ArgumentError, 'inspect blew up')
        def is_a?(*) = super
      end
      k = define_struct('Boom') { required :v, :value }
      allow(Oj).to receive(:dump).and_raise(ArgumentError, 'dump blew up')
      expect { avro.to_datum(k.new(v: boom.new)) }.to raise_error(ArgumentError, 'dump blew up')
    end
  end

  describe 'structs, arrays and unions (AV-B22)' do
    it 'AV-B22: converts nested structs with their own serialize names' do
      define_struct('Dn::Inner') do
        required :full_name, :string
        serialize :avro, full_name: 'fullName'
      end
      k = define_struct('Dn::Outer') do
        required :inner, Dn::Inner
        optional :list, :array, of: Dn::Inner
      end
      expect(avro.to_datum(k.new(inner: { full_name: 'A' }, list: [{ full_name: 'B' }]))).to eq(
        'inner' => { 'fullName' => 'A' }, 'list' => [{ 'fullName' => 'B' }]
      )
    end

    it 'AV-B22: matches union members by Ruby type, :value last' do
      define_struct('Du::Box') { required :n, :integer }
      k = define_struct('Du::Mast') { required :v, :union, of: [:integer, Du::Box, :string, :float] }
      expect(avro.to_datum(k.new(v: 5))).to eq('v' => 5)
      expect(avro.to_datum(k.new(v: 'x'))).to eq('v' => 'x')
      expect(avro.to_datum(k.new(v: { n: 1 }))).to eq('v' => { 'n' => 1 })
    end

    it 'AV-B22: passes a value that matches no member through' do
      k = define_struct('Du2') { required :v, :union, of: %i[integer string] }
      instance = k.new(v: 1)
      instance.instance_variable_set(:@v, 2.5)
      expect(avro.to_datum(instance)).to eq('v' => 2.5)
    end

    it 'AV-B22: a union value member is written as JSON text (decision B4)' do
      k = define_struct('Du3') { required :v, :union, of: %i[integer value] }
      expect(avro.to_datum(k.new(v: 7))).to eq('v' => 7)
      expect(avro.to_datum(k.new(v: { 'a' => 1 }))).to eq('v' => '{"a":1}')
    end
  end

  describe 'overrides (AV-B23)' do
    it 'AV-B23: sends values as held, Symbols as Strings deeply, and does not check times' do
      k = define_struct('Ov1') do
        required :a, :value, avro: { type: { type: 'map', values: 'string' } }
        required :t, :time, avro: { type: 'long' }
        required :s, :symbol, avro: { type: 'string' }
      end
      datum = avro.to_datum(k.new(a: { k: :v, n: [:x] }, t: Time.utc(2026, 1, 1, 0, 0, 0, Rational(123_456_789, 1000)), s: :sym))
      expect(datum['a']).to eq('k' => 'v', 'n' => ['x'])
      expect(datum['t']).to be_a(Time)
      expect(datum['s']).to eq('sym')
    end

    it 'AV-B23: a :value overridden to a string type still travels as JSON text' do
      k = define_struct('Ov2') do
        required :a, :value, avro: { type: 'string' }
        required :b, :value, avro: { type: { type: 'string', 'x-note': 1 } }
        optional :c, :value, avro: { type: %w[null string] }
        required :d, :value, avro: { type: { type: 'map', values: 'long' } }
      end
      datum = avro.to_datum(k.new(a: { x: 1 }, b: [1], c: 'text', d: { z: 1 }))
      expect(datum).to eq('a' => '{"x":1}', 'b' => '[1]', 'c' => '"text"', 'd' => { 'z' => 1 })
    end

    it 'AV-B23: converts struct instances by their own mappings' do
      define_struct('Ov3::In') do
        required :full_name, :string
        serialize :avro, full_name: 'fullName'
      end
      k = define_struct('Ov3::Out') { required :v, Ov3::In, avro: { type: { type: 'map', values: 'string' } } }
      expect(avro.to_datum(k.new(v: { full_name: 'x' }))).to eq('v' => { 'fullName' => 'x' })
    end
  end

  describe ':value (AV-B24)' do
    let(:k) { define_struct('Val') { required :blob, :value } }

    it 'AV-B24: writes the JSON text to_json would write' do
      value = { sym: :s, dec: BigDecimal('1.5'), day: Date.new(2026, 1, 2), list: [1, nil, 2.5] }
      expect(avro.to_datum(k.new(blob: value))['blob']).to eq('{"sym":"s","dec":"1.5","day":"2026-01-02","list":[1,null,2.5]}')
    end

    it 'AV-B24: reads fractions as BigDecimal and keeps times and decimals as Strings' do
      text = '{"a":1.5,"b":"2026-01-02T00:00:00Z","c":[1,2],"^o":"Object"}'
      loaded = avro.from_datum(k, { 'blob' => text }).blob
      expect(loaded).to eq('a' => BigDecimal('1.5'), 'b' => '2026-01-02T00:00:00Z', 'c' => [1, 2], '^o' => 'Object')
    end

    it 'AV-B24: refuses JSON that does not parse, with no cause and no text' do
      expect { avro.from_datum(k, { 'blob' => '{broken' }) }.to raise_error(ArgumentError) { |e|
        expect(e.message).to match(/\AFieldStruct::Avro \(Val#blob\) holds :value JSON that doesn't parse \(\w+\)\z/)
        expect(e.message).not_to include('broken')
        expect(e.cause).to be_nil
      }
    end

    it 'AV-B24: names the path inside anonymous structs' do
      inner = Class.new(FieldStruct::Base) { required :meta, :value }
      holder = define_struct('NoteMast2') { required :inner, inner }
      expect { avro.from_datum(holder, { 'inner' => { 'meta' => '[1,' } }) }
        .to raise_error(ArgumentError, /\AFieldStruct::Avro \(NoteMast2#inner\.meta\) holds :value JSON/)
    end
  end

  describe 'from_datum (AV-B25..AV-B29)' do
    it 'AV-B25: builds from Avro names with field names, nested and element-wise' do
      define_struct('Fd::In') do
        required :full_name, :string
        serialize :avro, full_name: 'fullName'
      end
      k = define_struct('Fd::Out') do
        required :inner, Fd::In
        optional :list, :array, of: Fd::In
        required :kind, :symbol
      end
      built = avro.from_datum(k, { 'inner' => { 'fullName' => 'A' }, 'list' => [{ 'fullName' => 'B' }], 'kind' => 'x' })
      expect(built.inner.full_name).to eq('A')
      expect(built.list.map(&:full_name)).to eq(['B'])
      expect(built.kind).to eq(:x)
    end

    it 'AV-B26: re-zones times to the field zone' do
      k = define_struct('Zoned') do
        required :utc, :time, zone: 'UTC'
        required :fixed, :time, zone: '+05:00'
        required :named, :time, zone: 'America/Denver'
        required :plain, :time
      end
      utc = Time.utc(2026, 7, 1, 14, 0, 0)
      built = avro.from_datum(k, { 'utc' => utc, 'fixed' => utc, 'named' => utc, 'plain' => utc })
      expect(built.utc.utc_offset).to eq(0)
      expect(built.fixed.utc_offset).to eq(5 * 3600)
      expect(built.named.utc_offset).to eq(-6 * 3600)
      expect(built.named).to eq(utc)
      expect(built.plain).to eq(utc)
      expect(utc).to be_utc
    end

    it 'AV-B26: the DateTime round trip decodes with the zone offset' do
      k = define_struct('Zoned2') { required :at, :datetime, zone: 'America/Denver' }
      built = round_trip(k.new(at: '2026-07-01T08:00:00'))
      expect(built.at.offset).to eq(Rational(-6, 24))
    end

    it 'AV-B27: raises for an unknown enum symbol, naming the field and not the value when sensitive' do
      k = define_struct('Status::V1') { required :s, :symbol, enum: %i[a b] }
      expect { avro.from_datum(k, { 's' => 'void' }) }.to raise_error(
        ArgumentError, "FieldStruct::Avro: Status::V1#s is :void, which isn't one of the field's enum symbols; " \
                       'give the reader avro: {enum_default:} to read new ones'
      )
      secret = define_struct('Status::V2') { required :s, :symbol, enum: %i[a b], sensitive: true }
      expect { avro.from_datum(secret, { 's' => 'void' }) }.to raise_error(
        ArgumentError, /\AFieldStruct::Avro: Status::V2#s is a sensitive symbol, which isn't one of/
      )
    end

    it 'AV-B27: reads an unknown symbol as enum_default, and passes a non-String through' do
      k = define_struct('Status::V3') { required :s, :symbol, enum: %i[a b], avro: { enum_default: :a } }
      expect(avro.from_datum(k, { 's' => 'void' }).s).to eq(:a)
      plain = define_struct('Status::V4') { required :s, :symbol, enum: %i[a b] }
      expect(avro.from_datum(plain, { 's' => 7 })).not_to be_valid
    end

    it 'AV-B27: does not check a field that has its own avro: type' do
      k = define_struct('Status::V5') { required :s, :symbol, enum: %i[a b], avro: { type: 'string' } }
      expect(avro.from_datum(k, { 's' => 'void' })).not_to be_valid
    end

    it 'AV-B28: loads a union Hash through the struct whose keys match, else as is' do
      define_struct('Ul::A') { required :a, :integer }
      define_struct('Ul::B') do
        required :b, :integer
        optional :c, :integer
      end
      k = define_struct('Ul::Mast') { required :v, :union, of: [Ul::A, Ul::B, :string] }
      expect(avro.from_datum(k, { 'v' => { 'a' => 1 } }).v).to be_a(Ul::A)
      expect(avro.from_datum(k, { 'v' => { 'b' => 1, 'c' => nil } }).v).to be_a(Ul::B)
      expect(avro.from_datum(k, { 'v' => 'plain' }).v).to eq('plain')
    end

    it 'AV-B29: loads override Hashes, Arrays of Hashes and re-zones Times' do
      define_struct('Ol::In') { required :a, :integer }
      k = define_struct('Ol::Out') do
        required :one, Ol::In, avro: { type: { type: 'map', values: 'long' } }
        required :many, :array, of: Ol::In, avro: { type: { type: 'array', items: 'string' } }
        required :at, :time, zone: '+02:00', avro: { type: 'long' }
        required :raw, :integer, avro: { type: 'long' }
      end
      utc = Time.utc(2026, 1, 1)
      built = avro.from_datum(k, { 'one' => { 'a' => 1 }, 'many' => [{ 'a' => 2 }], 'at' => utc, 'raw' => 3 })
      expect(built.one).to be_a(Ol::In)
      expect(built.many.map(&:a)).to eq([2])
      expect(built.at.utc_offset).to eq(7200)
      expect(built.raw).to eq(3)
    end

    it 'AV-B25: leaves out keys the datum lacks so the struct default applies' do
      k = define_struct('Dflt') do
        required :a, :integer
        optional :b, :integer, default: 9
      end
      expect(avro.from_datum(k, { 'a' => 1 }).b).to eq(9)
    end
  end

  describe 'encode and decode (AV-B32..AV-B36, AV-I9)' do
    let(:beacon) do
      define_struct('Harbor::Beacon') do
        required :id, :uuid
        required :reach, :big_decimal, round: 2
        required :lit, :time, zone: 'America/Denver'
        required :tower, :symbol, enum: %i[new used]
        optional :codes, :array, of: :string
        optional :meta, :value
        required :count, :integer, default: 0
      end
    end

    it 'AV-I9: round trips an instance, the spec example' do
      instance = beacon.new(id: SecureRandom.uuid, reach: '19.90', lit: '2026-07-01T08:00:00', tower: :new, codes: %w[a b],
                            meta: { 'k' => [1, 'x'] })
      bytes = avro.encode(instance)
      expect(bytes).to be_a(String)
      expect(bytes.encoding).to eq(Encoding::BINARY)
      expect(avro.decode(beacon, bytes)).to eq(instance)
    end

    it 'AV-I9: round trips nil optionals and every timestamp precision' do
      instance = beacon.new(id: SecureRandom.uuid, reach: '0.05', lit: Time.utc(2026, 1, 1, 0, 0, 0, 1), tower: :used)
      %i[micros nanos].each { |ts| expect(round_trip(instance, timestamp: ts)).to eq(instance) }
      ms = beacon.new(id: SecureRandom.uuid, reach: '0.05', lit: Time.utc(2026, 1, 1, 0, 0, 0, 5000), tower: :used)
      expect(round_trip(ms, timestamp: :millis)).to eq(ms)
    end

    it 'AV-B32: does not validate field rules' do
      k = define_struct('Lax') { required :n, :integer, in: 1..3 }
      expect(avro.decode(k, avro.encode(k.new(n: 99))).n).to eq(99)
    end

    it 'AV-B35: round trips a 63-bit integer and refuses 2**64' do
      k = define_struct('Big') { required :n, :integer }
      expect(round_trip(k.new(n: 2**62)).n).to eq(2**62)
      expect { avro.encode(k.new(n: 2**64)) }.to raise_error(StandardError)
    end

    it 'AV-B34: lets the avro gem refuse a decimal past its precision or scale' do
      k = define_struct('Dec') { required :reach, :big_decimal, round: 2, avro: { precision: 4 } }
      expect { avro.encode(k.new(reach: '12345.67')) }.to raise_error(StandardError)
      loose = define_struct('Dec2') { required :reach, :big_decimal, avro: { scale: 2 } }
      expect { avro.encode(loose.new(reach: '1.239')) }.to raise_error(StandardError)
    end

    it 'AV-B33: re-raises the avro type error for a valid struct' do
      k = define_struct('Typed') { required :n, :integer, avro: { type: 'string' } }
      expect { avro.encode(k.new(n: 5)) }.to raise_error(Avro::IO::AvroTypeError)
    end

    it 'AV-B33: raises an ArgumentError naming the problems, with no cause, for an invalid struct' do
      k = define_struct('Signup') { required :id, :integer }
      expect { avro.encode(k.new(id: 'abc')) }.to raise_error(ArgumentError) { |e|
        expect(e.message).to start_with("FieldStruct::Avro can't encode an invalid Signup: Id could not be coerced")
        expect(e.cause).to be_nil
      }
    end

    it 'AV-B36: decodes with the class schema as both writer and reader' do
      k = define_struct('Plain2') { required :a, :integer }
      expect(avro.decode(k, avro.encode(k.new(a: 4))).a).to eq(4)
    end

    it 'AV-I9: a generated-values round trip over decimals, times and strings' do
      k = define_struct('Gen') do
        required :reach, :big_decimal, round: 4
        required :at, :time
        required :s, :string
        required :f, :float
        required :n, :integer
      end
      rng = Random.new(42)
      50.times do
        instance = k.new(reach: BigDecimal(rng.rand(-10**9..(10**9))) / 10_000,
                         at: Time.at(rng.rand(0..2_000_000_000), rng.rand(0..999_999), :usec).utc,
                         s: Array.new(rng.rand(0..20)) { rng.rand(32..0x2FF).chr('UTF-8') }.join,
                         f: rng.rand * 1e6, n: rng.rand(-2**62..(2**62)))
        expect(round_trip(instance)).to eq(instance)
      end
    end

    it 'AV-I9: round trips unions, arrays of structs, enums and :value members' do
      define_struct('Rt::Box') { required :n, :integer }
      define_struct('Rt::Tag') do
        required :label, :string
        required :score, :float
      end
      k = define_struct('Rt::Mast') do
        required :u, :union, of: [:integer, :string, Rt::Box]
        optional :boxes, :array, of: Rt::Box
        optional :codes, :array, of: Rt::Tag
        optional :v, :union, of: %i[integer value]
      end
      [5, 'x', { n: 1 }].each do |u|
        instance = k.new(u: u, boxes: [{ n: 2 }, nil], codes: [{ label: 'l', score: 1.5 }], v: { 'a' => [1] })
        expect(round_trip(instance)).to eq(instance)
      end
      expect(round_trip(k.new(u: 1, v: 3)).v).to eq(3)
    end

    it 'AV-I9: round trips with serialize names and a custom serialization' do
      k = define_struct('Ser') do
        required :first_name, :string
        serialize :kafka, first_name: 'first'
      end
      instance = k.new(first_name: 'Ada')
      expect(round_trip(instance, serialization: :kafka)).to eq(instance)
      expect(avro.to_datum(instance, serialization: :kafka)).to eq('first' => 'Ada')
    end

    it 'AV-I9: round trips from_datum(to_datum)' do
      k = define_struct('Dt') do
        required :reach, :big_decimal, round: 2
        required :kind, :symbol, enum: %i[a b]
      end
      instance = k.new(reach: '1.25', kind: :b)
      expect(avro.from_datum(k, avro.to_datum(instance))).to eq(instance)
    end

    it 'AV-B24: a :value overridden to a string round trips like from_json' do
      k = define_struct('Ov4') { required :a, :value, avro: { type: 'string' } }
      instance = k.new(a: { 'x' => [1, 'y'] })
      expect(round_trip(instance)).to eq(instance)
    end
  end
end
