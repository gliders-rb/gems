# frozen_string_literal: true

RSpec.describe 'FieldStruct::Avro evolution' do
  let(:avro) { FieldStruct::Avro }
  let(:tail) { '. The avro gem would decode them as the wrong value, or fail; this is not a compatible schema change' }

  # The older class lives in module Wr, the newer in Rd; the writer schema is the older one renamed into Rd,
  # since Avro matches record names.
  def pair(name, old, new)
    [define_struct("Wr::#{name}", &old), define_struct("Rd::#{name}", &new)]
  end

  def writer_of(klass, **)
    Oj.load(Oj.dump(avro.schema(klass, **), mode: :compat).gsub(/\bWr\b/, 'Rd'))
  end

  def evolve(old, new, attrs, name: "E#{rand(10**9)}", **options)
    older, newer = pair(name, old, new)
    bytes = avro.encode(older.new(attrs), **options)
    avro.decode(newer, bytes, writer_schema: writer_of(older, **options), **options)
  end

  def refusal(old, new, **options)
    older, newer = pair("R#{rand(10**9)}", old, new)
    avro.decode(newer, avro.encode(older.new(yield)), writer_schema: writer_of(older), **options)
  end

  describe 'writer_schema: forms (AV-B38, AV-B43)' do
    let(:old) { proc { required :id, :integer } }
    let(:new) { proc { required :id, :integer } }

    it 'AV-B38: accepts a Hash, a JSON String and a parsed Avro::Schema' do
      older, newer = pair('Forms', old, new)
      bytes = avro.encode(older.new(id: 4))
      hash = writer_of(older)
      [hash, Oj.dump(hash, mode: :compat), Avro::Schema.parse(Oj.dump(hash, mode: :compat))].each do |form|
        expect(avro.decode(newer, bytes, writer_schema: form).id).to eq(4)
      end
    end

    it 'AV-B43: a schema from a registry client (parsed Avro::Schema) decodes' do
      older, newer = pair('Reg', old, new)
      parsed = Avro::Schema.parse(Oj.dump(writer_of(older), mode: :compat))
      expect(avro.decode(newer, avro.encode(older.new(id: 9)), writer_schema: parsed).id).to eq(9)
    end

    it 'AV-B38: refuses any other form' do
      k = define_struct('FormsBad') { required :id, :integer }
      expect { avro.decode(k, avro.encode(k.new(id: 1)), writer_schema: :nope) }.to raise_error(
        ArgumentError, 'FieldStruct::Avro.decode: writer_schema: expects a Hash, a JSON String or an Avro::Schema, got Symbol'
      )
    end

    it 'AV-B38: refuses invalid JSON and a schema the avro gem cannot parse' do
      k = define_struct('FormsBad2') { required :id, :integer }
      bytes = avro.encode(k.new(id: 1))
      ['{not json', { 'type' => 'strng' }].each do |bad|
        expect { avro.decode(k, bytes, writer_schema: bad) }.to raise_error(
          ArgumentError, /\AFieldStruct::Avro\.decode: writer_schema: isn't a valid Avro schema \(\w+(::\w+)*: /
        )
      end
    end

    it 'AV-B38: a writer schema for the class itself decodes like none' do
      k = define_struct('Same') { required :id, :integer }
      expect(avro.decode(k, avro.encode(k.new(id: 3)), writer_schema: avro.schema(k)).id).to eq(3)
    end
  end

  describe 'absent fields (AV-B40, AV-B42)' do
    it 'AV-B42: v1 {id} read as v2 {id, optional note} gives a nil note' do
      result = evolve(proc { required :id, :integer }, proc do
        required :id, :integer
        optional :note, :string
      end, { id: 1 })
      expect([result.id, result.note]).to eq([1, nil])
    end

    it 'AV-B40: fields the writer lacked take the field_struct default, including ones Avro cannot express' do
      result = evolve(proc { required :id, :integer }, proc do
        required :id, :integer
        required :day, :date, default: Date.new(2026, 1, 2)
        required :reach, :big_decimal, round: 2, default: BigDecimal('1.50')
        required :stamp, :integer, default: -> { 42 }
        required :codes, :array, of: :string, default: %w[a]
        required :kind, :symbol, enum: %i[a b], default: :b
        required :must, :integer
      end, { id: 1 })
      expect(result.day).to eq(Date.new(2026, 1, 2))
      expect(result.reach).to eq(BigDecimal('1.50'))
      expect(result.stamp).to eq(42)
      expect(result.codes).to eq(%w[a])
      expect(result.kind).to eq(:b)
      expect(result.valid?).to be(false)
    end

    it 'AV-B40: a field the writer had keeps what was written, nil included' do
      result = evolve(proc do
        required :id, :integer
        optional :note, :string
      end, proc do
        required :id, :integer
        optional :note, :string, default: 'fallback'
      end, { id: 1 })
      expect(result.note).to be_nil
    end

    it 'AV-B40: works through nested structs' do
      define_struct('Wr::Inner') { required :a, :integer }
      define_struct('Rd::Inner') do
        required :a, :integer
        required :b, :integer, default: 7
      end
      older = define_struct('Wr::Outer') { required :inner, Wr::Inner }
      newer = define_struct('Rd::Outer') { required :inner, Rd::Inner }
      result = avro.decode(newer, avro.encode(older.new(inner: { a: 1 })), writer_schema: writer_of(older))
      expect(result.inner.b).to eq(7)
    end

    it 'AV-B40: works when the field is renamed by serialize' do
      result = evolve(proc { required :id, :integer }, proc do
        required :id, :integer
        required :first_name, :string, default: 'Ada'
        serialize :avro, first_name: 'firstName'
      end, { id: 1 })
      expect(result.first_name).to eq('Ada')
    end

    it 'AV-B40: an anonymous struct used in two fields reads each record as its writer wrote it' do
      anon_old = Class.new(FieldStruct::Base) { required :a, :integer }
      anon_new = Class.new(FieldStruct::Base) do
        required :a, :integer
        required :b, :integer, default: 5
      end
      older = define_struct('Wr::Twice') do
        required :x, anon_old
        required :y, anon_old
      end
      newer = define_struct('Rd::Twice') do
        required :x, anon_new
        required :y, anon_new
      end
      result = avro.decode(newer, avro.encode(older.new(x: { a: 1 }, y: { a: 2 })), writer_schema: writer_of(older))
      expect([result.x.b, result.y.b]).to eq([5, 5])
    end

    it 'AV-B42: a record name that does not match fails the avro gem and is reported as unreadable bytes' do
      k = define_struct('Wr::Named') { required :id, :integer }
      other = define_struct('Rd::Other') { required :id, :integer }
      expect { avro.decode(other, avro.encode(k.new(id: 1)), writer_schema: avro.schema(k)) }.to raise_error(ArgumentError) { |e|
        expect(e.message).to start_with("FieldStruct::Avro can't decode these bytes as Rd::Other (")
        expect(e.message).to end_with("they end early, or the writer schema given doesn't resolve against Rd::Other's (the cause says why)")
        expect(e.cause).not_to be_nil
      }
    end

    it 'AV-B42: a symbol the reader enum lacks is the AV-B27 error, or the enum_default' do
      old = proc { required :s, :symbol, enum: %i[a b c] }
      expect { evolve(old, proc { required :s, :symbol, enum: %i[a b] }, { s: :c }) }.to raise_error(
        ArgumentError, /isn't one of the field's enum symbols/
      )
      expect(evolve(old, proc { required :s, :symbol, enum: %i[a b], avro: { enum_default: :a } }, { s: :c }).s).to eq(:a)
    end
  end

  describe 'the resolution check (AV-B39, AV-B41)' do
    it 'AV-B39: refuses a decimal read at another scale' do
      expect do
        refusal(proc { required :reach, :big_decimal, round: 2 }, proc { required :reach, :big_decimal, round: 3 }) { { reach: '1.25' } }
      end.to raise_error(ArgumentError, "FieldStruct::Avro can't read these bytes: reach: written as decimal (scale 2), " \
                                        "read as decimal (scale 3)#{tail}")
    end

    it 'AV-B39: does not compare precision' do
      result = evolve(proc { required :reach, :big_decimal, round: 2, avro: { precision: 6 } },
                      proc { required :reach, :big_decimal, round: 2, avro: { precision: 12 } }, { reach: '1.25' })
      expect(result.reach).to eq(BigDecimal('1.25'))
    end

    it 'AV-B39 and AV-B41: refuses timestamps at another precision, including the call option' do
      old = proc { required :at, :time }
      expect { refusal(old, old, timestamp: :nanos) { { at: Time.utc(2026, 1, 1) } } }.to raise_error(
        ArgumentError, "FieldStruct::Avro can't read these bytes: at: written as timestamp-micros, read as timestamp-nanos#{tail}"
      )
    end

    it 'AV-B39: refuses a date read as a timestamp, a decimal read as a string and a string read as a decimal' do
      expect { refusal(proc { required :d, :date }, proc { required :d, :time }) { { d: Date.new(2026, 1, 1) } } }.to raise_error(
        ArgumentError, /d: written as date, read as timestamp-micros#{Regexp.escape(tail)}\z/
      )
      expect { refusal(proc { required :p, :big_decimal, round: 2 }, proc { required :p, :big_decimal }) { { p: '1.5' } } }.to raise_error(
        ArgumentError, /p: written as decimal \(scale 2\), read as string/
      )
      expect { refusal(proc { required :p, :big_decimal }, proc { required :p, :big_decimal, round: 2 }) { { p: '1.5' } } }.to raise_error(
        ArgumentError, /p: written as string, read as decimal \(scale 2\)/
      )
    end

    it 'AV-B39: joins several problems with "; " and names nested paths' do
      define_struct('Wr::Lamp') { required :reach, :big_decimal, round: 2 }
      define_struct('Rd::Lamp') { required :reach, :big_decimal, round: 3 }
      older = define_struct('Wr::Dispatch') do
        required :lines, :array, of: Wr::Lamp
        required :at, :time
      end
      newer = define_struct('Rd::Dispatch') do
        required :lines, :array, of: Rd::Lamp
        required :at, :time, avro: { timestamp: :nanos }
      end
      bytes = avro.encode(older.new(lines: [{ reach: '1.00' }], at: Time.utc(2026, 1, 1)))
      expect { avro.decode(newer, bytes, writer_schema: writer_of(older)) }.to raise_error(ArgumentError) { |e|
        expect(e.message).to eq(
          "FieldStruct::Avro can't read these bytes: lines[].reach: written as decimal (scale 2), read as decimal (scale 3); " \
          "at: written as timestamp-micros, read as timestamp-nanos#{tail}"
        )
      }
    end

    it 'AV-B39: lets plain promotions through, and uuid against string' do
      result = evolve(proc do
        required :n, :integer
        required :u, :uuid
      end, proc do
        required :n, :float
        required :u, :string
      end, { n: 7, u: '8b1f4d4a-0d0e-4b29-9f4d-6a1b3d3c9f00' })
      expect(result.n).to eq(7.0)
      expect(result.u).to eq('8b1f4d4a-0d0e-4b29-9f4d-6a1b3d3c9f00')
    end

    it 'AV-B39: refuses a time, date or decimal that went from optional to required, but not a plain string' do
      expect { refusal(proc { optional :at, :time }, proc { required :at, :time }) { { at: Time.utc(2026, 1, 1) } } }.to raise_error(
        ArgumentError
      ) { |e|
        expect(e.message).to include('at: written as a union with timestamp-micros, read as timestamp-micros outside one, ',
                                     'which the avro gem fails to decode (keep the field optional)')
      }
      expect(evolve(proc { optional :s, :string }, proc { required :s, :string }, { s: 'x' }).s).to eq('x')
    end

    it 'AV-B39: compares a recursive record once and terminates' do
      %w[Wr Rd].each do |space|
        node = Class.new(FieldStruct::Base)
        stub_const("#{space}::Node", node)
        node.class_eval do
          required :v, :integer
          optional :next_node, node
        end
      end
      result = avro.decode(Rd::Node, avro.encode(Wr::Node.new(v: 1, next_node: { v: 2 })), writer_schema: writer_of(Wr::Node))
      expect(result.next_node.v).to eq(2)
    end

    it 'AV-B39: compares map values, naming them {}' do
      decimal = ->(scale) { { 'type' => 'bytes', 'logicalType' => 'decimal', 'precision' => 10, 'scale' => scale } }
      map = ->(scale) { { 'type' => 'map', 'values' => decimal.call(scale) } }
      newer = define_struct('Rd::M') { required :m, :value, avro: { type: map.call(3) } }
      older = { 'type' => 'record', 'name' => 'M', 'namespace' => 'Rd', 'fields' => [{ 'name' => 'm', 'type' => map.call(2) }] }
      expect { avro.decode(newer, "\x00".b, writer_schema: older) }.to raise_error(
        ArgumentError, /m\{\}: written as decimal \(scale 2\), read as decimal \(scale 3\)/
      )
    end
  end
end
