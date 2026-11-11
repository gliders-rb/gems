# frozen_string_literal: true

RSpec.describe 'FieldStruct::Avro error hygiene' do
  let(:avro) { FieldStruct::Avro }
  let(:head) { "FieldStruct::Avro can't decode these bytes as Readings (" }
  let(:own) { 'they end early, or were written with another schema (pass writer_schema: for bytes from an older one)' }

  let(:readings) do
    define_struct('Readings') do
      required :name, :string
      required :n, :integer
      optional :codes, :array, of: :string
    end
  end

  describe 'unreadable bytes (AV-B37)' do
    it 'AV-B37: wraps bytes that end early, keeping the cause and the documented hint' do
      bytes = avro.encode(readings.new(name: 'abcdef', n: 3, codes: %w[a b]))
      expect { avro.decode(readings, bytes[0, 5]) }.to raise_error(ArgumentError) { |e|
        expect(e.message).to eq("#{head}#{e.cause.class.name}): #{own}")
        expect(e.cause).to be_a(EOFError)
      }
    end

    it 'AV-B37: wraps an empty String' do
      expect { avro.decode(readings, '') }.to raise_error(ArgumentError) { |e|
        expect(e.message).to start_with(head)
        expect(e.cause).to be_a(EOFError)
      }
    end

    it 'AV-B37: wraps the other failures of the avro gem, whatever their class' do
      ["\x02\x00\x12".b, "\x02\x03".b, "\xff\xff\xff\xff\xff\xff\xff\xff\xff\x7f".b].each do |bytes|
        expect { avro.decode(readings, bytes) }.to raise_error(ArgumentError) { |e|
          expect(e.message).to start_with(head)
          expect(e.cause).not_to be_nil
          expect(e.message).to end_with(own)
        }
      end
    end

    it 'AV-B37: leaves a conversion error raised after the bytes are read alone' do
      k = define_struct('Status') { required :s, :symbol, enum: %i[a b] }
      expect(avro.decode(k, avro.encode(k.new(s: :a))).s).to eq(:a)
      expect { avro.from_datum(k, { 's' => 'zzz' }) }.to raise_error(ArgumentError, /isn't one of the field's enum symbols/)
    end
  end

  describe 'error text (AV-B44, AV-B45)' do
    it 'AV-B44: the unreadable-bytes message does not carry the avro gem message, the cause does' do
      expect { avro.decode(readings, '') }.to raise_error(ArgumentError) { |e|
        expect(e.cause.message).not_to be_empty
        expect(e.message).not_to include(e.cause.message)
      }
    end

    it 'AV-B44: the invalid-instance message holds field errors and no avro text' do
      k = define_struct('Signup2') { required :id, :integer }
      expect { avro.encode(k.new(id: 'abc')) }.to raise_error(ArgumentError) { |e|
        expect(e.message).not_to include('AvroTypeError')
        expect(e.message).not_to match(/Expected .* got /)
        expect(e.cause).to be_nil
      }
    end

    it 'AV-B45: reports a named inner struct by its own name and an anonymous root by inspect' do
      define_struct('Hy::Pair') { required :updated, :time }
      holder = define_struct('Hy::Mast') { required :pair, Hy::Pair }
      nanos = Time.utc(2026, 10, 25, 21, 55, 12, Rational(123_456_789, 1000))
      expect { avro.to_datum(holder.new(pair: { updated: nanos })) }.to raise_error(
        ArgumentError, /\AFieldStruct::Avro: Hy::Pair#updated is /
      )
      anon = Class.new(FieldStruct::Base) { required :at, :time }
      expect { avro.to_datum(anon.new(at: nanos)) }.to raise_error(ArgumentError, /\AFieldStruct::Avro: #<Class:0x\h+>#at is /)
    end

    it 'AV-B45: chains the path through anonymous structs and keeps the sensitive flag from above' do
      inner = Class.new(FieldStruct::Base) { required :at, :time }
      holder = define_struct('Hy2::Mast') { required :inner, inner, sensitive: true }
      nanos = Time.utc(2026, 10, 25, 21, 55, 12, Rational(123_456_789, 1000))
      expect { avro.to_datum(holder.new(inner: { at: nanos })) }.to raise_error(
        ArgumentError, /\AFieldStruct::Avro: Hy2::Mast#inner\.at is a sensitive time, which has more precision/
      )
    end

    it 'AV-B45: does not echo a sensitive unknown symbol' do
      k = define_struct('Hy3') { required :s, :symbol, enum: %i[a b], sensitive: true }
      expect { avro.from_datum(k, { 's' => 'secret' }) }.to raise_error(ArgumentError) { |e|
        expect(e.message).to include('a sensitive symbol')
        expect(e.message).not_to include('secret')
      }
    end

    it 'AV-B46: documents the leak it cannot close, the avro gem type error for an override that does not fit' do
      k = define_struct('Leak') { required :n, :integer, avro: { type: 'string' } }
      expect { avro.encode(k.new(n: 5)) }.to raise_error(Avro::IO::AvroTypeError)
    end
  end
end
