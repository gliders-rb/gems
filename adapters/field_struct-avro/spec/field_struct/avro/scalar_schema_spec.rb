# frozen_string_literal: true

RSpec.describe 'FieldStruct::Avro.schema for scalars' do
  def parses!(klass, **options)
    Avro::Schema.parse(Oj.dump(FieldStruct::Avro.schema(klass, **options), mode: :compat))
  end

  describe 'the record (AV-B13, AV-B15)' do
    it 'AV-B13: names the record after the class and its namespace after the modules' do
      define_struct('Harbor::Beacon') { required :title, :string }
      expect(avro_schema(Harbor::Beacon)).to eq(
        'type' => 'record', 'name' => 'Beacon', 'namespace' => 'Harbor',
        'fields' => [{ 'name' => 'title', 'type' => 'string' }]
      )
    end

    it 'AV-B13: leaves out the namespace for a class without a module, and joins deep modules with dots' do
      define_struct('Flat') { required :a, :string }
      define_struct('One::Two::Deep') { required :a, :string }
      expect(avro_schema(Flat).keys).to eq(%w[type name fields])
      expect(avro_schema(One::Two::Deep)).to include('name' => 'Deep', 'namespace' => 'One.Two')
    end

    it 'AV-B13: refuses a class segment Avro cannot name' do
      holder = Module.new
      stub_const('Ugly', holder)
      bad = Class.new(FieldStruct::Base) { required :a, :string }
      stub_const('Ugly::Café', bad)
      expect do
        avro_schema(bad)
      end.to raise_error(ArgumentError, /FieldStruct::Avro: class Ugly::Café is named "Café", which Avro names can't be/)
    end

    it 'AV-B13: refuses a field name Avro cannot hold' do
      klass = define_struct('Contact2') do
        required :first_name, :string
        serialize :avro, first_name: 'first-name'
      end
      expect { avro_schema(klass) }.to raise_error(
        ArgumentError, /FieldStruct::Avro: field Contact2#first_name is named "first-name", which Avro names can't be/
      )
    end

    it 'AV-B15: keeps declaration order and uses the serialize :avro names' do
      klass = define_struct('Renamed') do
        required :first_name, :string
        required :age, :integer
        serialize :avro, first_name: 'firstName'
      end
      expect(avro_schema(klass)['fields'].map { |f| f['name'] }).to eq(%w[firstName age])
    end

    it 'AV-B3: uses another serialization when a struct declares it' do
      klass = define_struct('Mapped::Outer') do
        required :first_name, :string
        serialize :kafka, first_name: 'first_name_k'
      end
      expect(avro_schema(klass, serialization: :kafka)['fields'].first['name']).to eq('first_name_k')
      expect(avro_schema(klass, serialization: 'kafka')['fields'].first['name']).to eq('first_name_k')
    end

    it 'AV-B3: refuses a serialization nobody declares, listing the declared ones' do
      klass = define_struct('Mapped::Outer') do
        required :first_name, :string
        serialize :kafka, first_name: 'k'
      end
      expect { avro_schema(klass, serialization: :kafak) }.to raise_error(
        ArgumentError, 'FieldStruct::Avro: no struct in Mapped::Outer declares serialize :kafak (declared: [:avro, :kafka])'
      )
    end

    it 'AV-B3: always accepts :avro without a serialize' do
      klass = define_struct('Plain') { required :a, :string }
      expect { avro_schema(klass, serialization: :avro) }.not_to raise_error
    end
  end

  describe 'scalar mapping (AV-B4)' do
    let(:klass) do
      define_struct('Scalars') do
        required :bin, :binary
        required :id, :uuid
        required :loose_id, :uuid, format: /\A\d+\z/
        required :name, :string
        required :frozen, :immutable_string
        required :mail, :email
        required :site, :url
        required :blob, :value
        required :flag, :boolean
        required :count, :integer
        required :ratio, :float
        required :day, :date
        required :seen, :time
        required :stamp, :datetime
        required :kind, :symbol
      end
    end

    it 'AV-B4: maps every built-in type' do
      types = avro_schema(klass)['fields'].to_h { |f| [f['name'], f['type']] }
      expect(types).to eq(
        'bin' => 'bytes',
        'id' => { 'type' => 'string', 'logicalType' => 'uuid' },
        'loose_id' => 'string',
        'name' => 'string', 'frozen' => 'string', 'mail' => 'string', 'site' => 'string', 'blob' => 'string',
        'flag' => 'boolean', 'count' => 'long', 'ratio' => 'double',
        'day' => { 'type' => 'int', 'logicalType' => 'date' },
        'seen' => { 'type' => 'long', 'logicalType' => 'timestamp-micros' },
        'stamp' => { 'type' => 'long', 'logicalType' => 'timestamp-micros' },
        'kind' => 'string'
      )
      parses!(klass)
    end

    it 'AV-B4: a uuid with its own default format is still a uuid' do
      k = define_struct('Ids') { required :id, :uuid, format: FieldStruct::Types::UUID.default_format }
      expect(type_of(k, 'id')).to eq({ 'type' => 'string', 'logicalType' => 'uuid' })
    end

    it 'AV-I1: never maps an integer to int' do
      expect(type_of(klass, 'count')).to eq('long')
    end

    it 'AV-B4: refuses a custom type with the field named' do
      custom = Class.new(FieldStruct::Types::Base) do
        def coerce(value, **) = value
        def ruby_type = Object
      end
      stub_const('Weird', custom)
      k = define_struct('Odd') { required :w, custom }
      expect { avro_schema(k) }.to raise_error(
        ArgumentError, 'FieldStruct::Avro has no mapping for Weird (Odd#w (Avro Odd_w)); give the field avro: {type: …}'
      )
    end
  end

  describe 'decimals (AV-B5)' do
    it 'AV-B5: round: gives the scale and 38 the precision' do
      k = define_struct('Money') { required :reach, :big_decimal, round: 2 }
      expect(type_of(k, 'reach')).to eq('type' => 'bytes', 'logicalType' => 'decimal', 'precision' => 38, 'scale' => 2)
    end

    it 'AV-B5: :decimal is the same type' do
      k = define_struct('Money2') { required :reach, :decimal, round: 3 }
      expect(type_of(k, 'reach')).to include('scale' => 3)
    end

    it 'AV-B5: avro precision: and scale: win' do
      k = define_struct('Money3') do
        required :a, :big_decimal, round: 2, avro: { precision: 12 }
        required :fee, :big_decimal, avro: { scale: 2 }
        required :c, :big_decimal, round: 5, avro: { scale: 1 }
      end
      expect(type_of(k, 'a')).to include('precision' => 12, 'scale' => 2)
      expect(type_of(k, 'fee')).to include('precision' => 38, 'scale' => 2)
      expect(type_of(k, 'c')).to include('scale' => 1)
    end

    it 'AV-B5: no scale means a string' do
      k = define_struct('Money4') { required :rate, :big_decimal }
      expect(type_of(k, 'rate')).to eq('string')
    end

    it 'AV-B5: a negative scale is zero' do
      k = define_struct('Money5') { required :tens, :big_decimal, round: -1 }
      expect(type_of(k, 'tens')).to include('scale' => 0)
    end

    it 'AV-B5: a scale equal to the precision is allowed' do
      k = define_struct('Money6') { required :a, :big_decimal, round: 5, avro: { precision: 5 } }
      expect(type_of(k, 'a')).to include('precision' => 5, 'scale' => 5)
    end

    it 'AV-B5: refuses what Avro cannot hold' do
      ints = define_struct('Bad1') { required :a, :big_decimal, round: 2, avro: { precision: '12' } }
      low = define_struct('Bad2') { required :a, :big_decimal, round: 2, avro: { precision: 0 } }
      high = define_struct('Bad3') { required :a, :big_decimal, round: 40 }
      expect { avro_schema(ints) }.to raise_error(
        ArgumentError, %(FieldStruct::Avro can't describe Bad1#a: decimal precision and scale must be integers, got "12" and 2)
      )
      expect { avro_schema(low) }.to raise_error(ArgumentError, "FieldStruct::Avro can't describe Bad2#a: precision 0 must be at least 1")
      expect { avro_schema(high) }.to raise_error(
        ArgumentError, "FieldStruct::Avro can't describe Bad3#a: scale 40 is more than precision 38; raise avro: {precision:}"
      )
    end
  end

  describe 'timestamps (AV-B6)' do
    let(:klass) do
      define_struct('Stamped') do
        required :at, :time
        required :precise, :datetime, avro: { timestamp: :nanos }
      end
    end

    it 'AV-B6: follows the call option and lets the field beat it' do
      expect(type_of(klass, 'at')['logicalType']).to eq('timestamp-micros')
      expect(type_of(klass, 'at', timestamp: :millis)['logicalType']).to eq('timestamp-millis')
      expect(type_of(klass, 'at', timestamp: :nanos)['logicalType']).to eq('timestamp-nanos')
      expect(type_of(klass, 'precise', timestamp: :millis)['logicalType']).to eq('timestamp-nanos')
      parses!(klass, timestamp: :nanos)
    end

    it 'AV-B6: refuses a bad per-field precision from schema' do
      k = define_struct('BadStamp') { required :at, :time, avro: { timestamp: :seconds } }
      expect { avro_schema(k) }.to raise_error(
        ArgumentError, 'FieldStruct::Avro (BadStamp#at) avro: {timestamp:} must be one of [:micros, :nanos, :millis], got :seconds'
      )
    end
  end

  describe 'optional and default (AV-B7, AV-B8)' do
    it 'AV-B7: required with no default is a bare field' do
      k = define_struct('R1') { required :a, :string }
      expect(avro_schema(k)['fields']).to eq([{ 'name' => 'a', 'type' => 'string' }])
    end

    it 'AV-B7: required with a usable default is not nullable' do
      k = define_struct('R2') { required :a, :integer, default: 5 }
      expect(avro_schema(k)['fields']).to eq([{ 'name' => 'a', 'type' => 'long', 'default' => 5 }])
    end

    it 'AV-B7: optional with no default is null first with a null default' do
      k = define_struct('R3') { optional :a, :string }
      field = avro_schema(k)['fields'].first
      expect(field).to eq({ 'name' => 'a', 'type' => %w[null string], 'default' => nil })
      expect(field).to have_key('default')
    end

    it 'AV-B7: optional with a usable default puts null last' do
      k = define_struct('R4') { optional :a, :string, default: 'x' }
      expect(avro_schema(k)['fields']).to eq([{ 'name' => 'a', 'type' => %w[string null], 'default' => 'x' }])
    end

    it 'AV-B7: keeps the key order name, doc, type, default, x-fs-sensitive' do
      k = define_struct('R5') { required :a, :integer, default: 1, desc: 'The a', sensitive: true }
      expect(avro_schema(k)['fields'].first.keys).to eq(%w[name doc type default x-fs-sensitive])
      expect(avro_schema(k)['fields'].first).to include('doc' => 'The a', 'x-fs-sensitive' => true)
    end

    it 'AV-B7: an optional override that is a union gets null first' do
      k = define_struct('R6') { optional :a, :string, avro: { type: %w[string null] } }
      expect(avro_schema(k)['fields'].first['type']).to eq(%w[null string])
    end

    it 'AV-B8: writes only literals of the field Avro type' do
      k = define_struct('Defaults') do
        required :flag, :boolean, default: false
        required :n, :integer, default: 0
        required :x, :float, default: 1
        required :y, :float, default: 2.5
        required :inf, :float, default: Float::INFINITY
        required :s, :string, default: ''
        required :sym, :symbol, default: :a
        required :enum, :symbol, enum: %i[a b], default: :b
        required :day, :date, default: Date.new(2026, 1, 1)
        required :bin, :binary, default: 'x'
        required :blob, :value, default: 'x'
        required :call, :integer, default: -> { 1 }
        required :list, :array, of: :string, default: []
        required :dec, :big_decimal, default: BigDecimal('1')
      end
      defaults = avro_schema(k)['fields'].to_h { |f| [f['name'], f.fetch('default', :none)] }
      expect(defaults).to eq(
        'flag' => false, 'n' => 0, 'x' => 1.0, 'y' => 2.5, 'inf' => :none, 's' => '', 'sym' => 'a', 'enum' => 'b',
        'day' => :none, 'bin' => :none, 'blob' => :none, 'call' => :none, 'list' => :none, 'dec' => :none
      )
      expect(defaults['x']).to be_a(Float)
      parses!(k)
    end
  end

  describe 'enums (AV-B9)' do
    it 'AV-B9: makes a named enum with no namespace key' do
      k = define_struct('Tower::Beacon') { required :tower, :symbol, enum: %i[new used] }
      expect(type_of(k, 'tower')).to eq('type' => 'enum', 'name' => 'Beacon_tower', 'symbols' => %w[new used])
    end

    it 'AV-B9: adds enum_default' do
      k = define_struct('Tower2') { required :tower, :symbol, enum: %i[new used], avro: { enum_default: :new } }
      expect(type_of(k, 'tower')).to eq('type' => 'enum', 'name' => 'Tower2_tower', 'symbols' => %w[new used], 'default' => 'new')
    end

    it 'AV-B9: falls back to a string for avro enum: false or names Avro cannot use' do
      k = define_struct('Shelf3') do
        required :a, :symbol, enum: %i[x y], avro: { enum: false }
        required :b, :symbol, enum: [:'not valid', :ok]
        required :c, :symbol
      end
      expect(type_of(k, 'a')).to eq('string')
      expect(type_of(k, 'b')).to eq('string')
      expect(type_of(k, 'c')).to eq('string')
    end

    it 'AV-B9: a bad enum_default fails the avro gem parse (AV-B30)' do
      k = define_struct('Shelf4') { required :a, :symbol, enum: %i[x y], avro: { enum_default: :zzz } }
      expect { avro_schema(k) }.to raise_error(ArgumentError, /Shelf4 doesn't make a valid Avro schema/)
    end

    it 'AV-B9: keeps enum symbols and defaults of a sensitive field in the schema' do
      k = define_struct('Shelf5') { required :a, :symbol, enum: %i[x y], sensitive: true, default: :x }
      field = avro_schema(k)['fields'].first
      expect(field).to include('x-fs-sensitive' => true, 'default' => 'x')
      expect(field['type']['symbols']).to eq(%w[x y])
    end

    it 'AV-B9: does not freeze the class enum: Array' do
      symbols = %i[x y]
      k = define_struct('Shelf6') { required :a, :symbol, enum: symbols }
      avro_schema(k)
      expect(k.metadata[:a].options[:enum]).not_to be_frozen
    end
  end

  describe 'the avro: type override (AV-B16)' do
    it 'AV-B16: replaces the mapping with the override verbatim, Symbols as Strings' do
      k = define_struct('Over') do
        required :a, :integer, avro: { type: :string }
        required :b, :string, avro: { type: { type: :fixed, name: 'F', size: 4 } }
        required :c, :integer, avro: { type: nil }
      end
      expect(type_of(k, 'a')).to eq('string')
      expect(type_of(k, 'b')).to eq({ 'type' => 'fixed', 'name' => 'F', 'size' => 4 })
      expect(type_of(k, 'c')).to eq('long')
    end

    it 'AV-B16: still wraps the override with optional and default rules' do
      k = define_struct('Over2') { optional :a, :integer, avro: { type: 'string' } }
      expect(avro_schema(k)['fields'].first).to eq({ 'name' => 'a', 'type' => %w[null string], 'default' => nil })
    end

    it 'AV-B30: fails at schema for an override the avro gem rejects' do
      [%w[Typo strng], ['Typo2', false]].each do |name, bad|
        k = define_struct(name) { required :a, :integer, avro: { type: bad } }
        expect { avro_schema(k) }.to raise_error(ArgumentError, /#{name} doesn't make a valid Avro schema \(check the avro: options/)
      end
    end
  end

  describe 'union members and elements carry no options (AV-B18)' do
    it 'AV-B18: a big_decimal union member is a string' do
      k = define_struct('Members') { required :v, :union, of: %i[big_decimal integer] }
      expect(type_of(k, 'v')).to eq(%w[long string])
    end
  end

  it 'AV-I6: returns a fresh copy each call' do
    k = define_struct('Fresh') { required :a, :symbol, enum: %i[x y] }
    first = avro_schema(k)
    first['fields'].first['type']['symbols'] << 'z'
    first['fields'] << {}
    expect(avro_schema(k)['fields'].size).to eq(1)
    expect(avro_schema(k)['fields'].first['type']['symbols']).to eq(%w[x y])
  end
end
