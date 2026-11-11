# frozen_string_literal: true

RSpec.describe FieldStruct::Types::String do
  subject(:type) { described_class.new }

  it 'FS-B164: ruby_type is String' do
    expect(type.ruby_type).to eq(String)
  end

  it 'declares format, enum and strict (in that order)' do
    schema = described_class.option_schema
    expect(schema.keys).to eq(%i[format enum strict])
    expect(schema[:format][:type]).to eq([Regexp, Symbol])
    expect(schema[:enum][:type]).to eq([Array])
    expect(schema[:strict][:type]).to eq([TrueClass, FalseClass])
  end

  describe 'FS-B52 coercion' do
    it 'returns nil for nil (FS-I16)' do
      expect(type.coerce(nil)).to be_nil
    end

    it 'passes Strings through unchanged, whitespace preserved' do
      expect(type.coerce('  x ')).to eq('  x ')
    end

    it 'calls to_s on everything else' do
      expect(type.coerce(:sym)).to eq('sym')
      expect(type.coerce(12.0)).to eq('12.0')
      expect(type.coerce(7)).to eq('7')
      expect(type.coerce(true)).to eq('true')
      expect(type.coerce([1, 2])).to eq('[1, 2]')
      expect(type.coerce({ a: 1 })).to eq({ a: 1 }.to_s)
    end

    it 'tolerates pass-through options as keywords' do
      expect(type.coerce('x', avro_doc: 'y', enum: %w[x])).to eq('x')
    end
  end

  describe 'FS-B53 strict: true' do
    it 'accepts String, Symbol, Integer and to_str responders' do
      to_str = Class.new { def to_str = 'ts' }.new
      expect(type.coerce('a', strict: true)).to eq('a')
      expect(type.coerce(:a, strict: true)).to eq('a')
      expect(type.coerce(5, strict: true)).to eq('5')
      expect(type.coerce(to_str, strict: true)).to eq(to_str.to_s)
    end

    it 'refuses everything else with a class-only TypeError' do
      strict_message = /\AString fields with strict: true expect .* #to_str, got an? \w+\z/
      [1.5, BigDecimal('1'), Rational(1, 2), Complex(1, 1), true, false, {}, [], Time.now, Object.new].each do |value|
        expect { type.coerce(value, strict: true) }.to raise_error(TypeError, strict_message)
      end
    end

    it 'names only the class' do
      expect { type.coerce(12.5, strict: true) }.to raise_error(TypeError, /got a Float\z/)
    end

    it 'treats strict: false and nil as the default' do
      expect(type.coerce(1.5, strict: false)).to eq('1.5')
      expect(type.coerce(1.5, strict: nil)).to eq('1.5')
    end
  end

  describe 'FS-B33 / FS-B161 missing?' do
    it 'FS-B33: agrees with String#strip for every code point and for invalid bytes, alone or padded' do
      verdict = lambda do |&probe|
        probe.call
      rescue StandardError => e
        e.class
      end
      disagreements = (0..0x10FFFF).filter_map do |code|
        next if (0xD800..0xDFFF).cover?(code)

        char = [code].pack('U')
        [char, " #{char} ", "a#{char}", "\0#{char}\0"].find do |text|
          type.missing?(text) != text.strip.empty?
        end
      end
      broken = { 'UTF-8' => ["\xC3", "\xFE", "\xE2\x82"], 'US-ASCII' => ["\xB0"], 'EUC-JP' => ["\xA4"],
                 'Shift_JIS' => ["\x83"], 'GB18030' => ["\x81"], 'Big5' => ["\xA4"] }
      invalid = broken.flat_map do |encoding, bytes|
        bytes.flat_map do |byte|
          [byte, " #{byte} ", "k#{byte}", "#{byte}\t", "\0#{byte}\0"].map { |text| text.b.force_encoding(encoding) }
        end
      end
      expect(invalid).to all(satisfy { |text| text.encoding.ascii_compatible? && !text.valid_encoding? })
      disagreements += invalid.reject do |text|
        verdict.call { type.missing?(text) } == verdict.call { text.strip.empty? }
      end
      expect(disagreements).to be_empty
    end

    it 'treats strings in non-ASCII-compatible encodings like strip does' do
      expect(type.missing?(' '.encode('UTF-16LE'))).to be(true)
      expect(type.missing?('a'.encode('UTF-16LE'))).to be(false)
    end

    it 'is true for nil, empty and whitespace-only' do
      [nil, '', '   ', "\t\n "].each { |v| expect(type.missing?(v)).to be(true) }
    end

    it 'is false for content' do
      expect(type.missing?(' a ')).to be(false)
    end
  end
end

RSpec.describe FieldStruct::Types::ImmutableString do
  subject(:type) { described_class.new }

  it 'is a String type with the same options' do
    expect(described_class.option_schema).to eq(FieldStruct::Types::String.option_schema)
    expect(type.ruby_type).to eq(String)
  end

  it 'FS-B54: returns a frozen copy and never freezes the input' do
    input = +'abc'
    result = type.coerce(input)
    expect(result).to eq('abc')
    expect(result).to be_frozen
    expect(result).not_to equal(input)
    expect(input).not_to be_frozen
  end

  it 'FS-B54: copies a frozen input too, and handles non-Strings and nil' do
    expect(type.coerce(:sym)).to eq('sym')
    expect(type.coerce(nil)).to be_nil
  end

  it 'honours strict: true' do
    expect { type.coerce(1.5, strict: true) }.to raise_error(TypeError)
  end

  it 'missing? matches :string' do
    expect(type.missing?('  ')).to be(true)
  end
end
