# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Float do
  subject(:type) { described_class.new }

  it 'FS-B164: ruby_type is Float' do
    expect(type.ruby_type).to eq(Float)
  end

  it 'declares round and in' do
    schema = described_class.option_schema
    expect(schema.keys).to eq(%i[round in])
    expect(schema[:round][:type]).to eq([Integer])
    expect(schema[:in][:type]).to eq([Array, Range])
  end

  it 'FS-B163: default_round is nil' do
    expect(described_class.default_round).to be_nil
  end

  it 'FS-B33: missing only for nil' do
    expect(type.missing?(nil)).to be(true)
    expect(type.missing?(0.0)).to be(false)
  end

  describe 'FS-B64 coercion' do
    it 'passes Floats and reads Integer, BigDecimal, Rational' do
      expect(type.coerce(1.5)).to eq(1.5)
      expect(type.coerce(2)).to eq(2.0)
      expect(type.coerce(BigDecimal('2.5'))).to eq(2.5)
      expect(type.coerce(Rational(1, 2))).to eq(0.5)
      expect(type.coerce(2)).to be_a(Float)
    end

    {
      '1_000.5' => 1000.5, ' 2.5 ' => 2.5, '1e3' => 1000.0, '.5' => 0.5, '5.' => 5.0, '017' => 17.0, '-3.5' => -3.5
    }.each do |input, expected|
      it "reads #{input.inspect}" do
        expect(type.coerce(input)).to eq(expected)
      end
    end

    ['', 'abc', 'NaN', 'Infinity', '-Infinity'].each do |input|
      it "refuses #{input.inspect}" do
        expect { type.coerce(input) }
          .to raise_error(ArgumentError, 'Float fields could not read a String as a number')
      end
    end

    it 'refuses a string whose value is not finite' do
      expect { type.coerce('1e400') }
        .to raise_error(ArgumentError, 'Float fields expect a finite number, got a non-finite String')
    end

    ['0x1A', '-0X1a', ' 0x10 ', '0x1.8p1'].each do |input|
      it "refuses hex-prefixed #{input.inspect}" do
        expect { type.coerce(input) }
          .to raise_error(ArgumentError, 'Float fields expect a base-10 number, got a String that is not one')
      end
    end

    it 'refuses NaN and infinities' do
      expect { type.coerce(Float::NAN) }.to raise_error(ArgumentError, 'Float fields expect a finite number, got a non-finite Float')
      expect { type.coerce(Float::INFINITY) }.to raise_error(ArgumentError, /non-finite Float/)
    end

    it 'raises TypeError for non-numeric objects' do
      expect { type.coerce(:sym) }.to raise_error(TypeError, "can't convert Symbol into Float")
      expect { type.coerce(Object.new) }.to raise_error(TypeError, /\Acan't convert Object into Float\z/)
    end

    it 'does not leak a quoted input through a RangeError' do
      expect { type.coerce(Complex(1, 2)) }
        .to raise_error(ArgumentError, 'Float fields could not read a Complex as a number') { |e| expect(e.cause).to be_nil }
    end
  end

  describe 'FS-B65 round:' do
    it 'rounds half up and returns a Float' do
      expect(type.coerce(2.5, round: 0)).to eql(3.0)
      expect(type.coerce(-2.5, round: 0)).to eql(-3.0)
      expect(type.coerce(1.25, round: 1)).to eql(1.3)
      expect(type.coerce(1234.0, round: -2)).to eql(1200.0)
      expect(type.coerce('2.5', round: 0)).to eql(3.0)
    end

    it 'does nothing for round: nil or absent' do
      expect(type.coerce(1.23456, round: nil)).to eq(1.23456)
    end

    it 'uses default_round of a subclass when round: is not declared' do
      subclass = Class.new(described_class) { def self.default_round = 1 }
      expect(subclass.new.coerce(1.26)).to eq(1.3)
      expect(subclass.new.coerce(1.26, round: 2)).to eq(1.26)
    end
  end
end
