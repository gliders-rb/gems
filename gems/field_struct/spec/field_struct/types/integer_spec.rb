# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Integer do
  subject(:type) { described_class.new }

  it 'FS-B164: ruby_type is Integer' do
    expect(type.ruby_type).to eq(Integer)
  end

  it 'declares in, base and strict (in that order)' do
    schema = described_class.option_schema
    expect(schema.keys).to eq(%i[in base strict])
    expect(schema[:in][:type]).to eq([Array, Range])
    expect(schema[:base][:type]).to eq([Integer])
  end

  it 'exposes MAX_DECIMAL_DIGITS' do
    expect(described_class::MAX_DECIMAL_DIGITS).to eq(4300)
  end

  it 'FS-B33: missing only for nil' do
    expect(type.missing?(nil)).to be(true)
    [0, '', false].each { |v| expect(type.missing?(v)).to be(false) }
  end

  describe 'FS-B60 strings' do
    {
      '42' => 42, '010' => 10, '007' => 7, ' 42 ' => 42, '1_000' => 1000, '-5' => -5, '+5' => 5
    }.each do |input, expected|
      it "reads #{input.inspect} as #{expected}" do
        expect(type.coerce(input)).to eq(expected)
      end
    end

    it 'reads a radix with base:' do
      expect(type.coerce('1A', base: 16)).to eq(26)
      expect(type.coerce('0x1A', base: 16)).to eq(26)
      expect(type.coerce('101', base: 2)).to eq(5)
    end

    it 'treats base: nil as 10' do
      expect(type.coerce('12', base: nil)).to eq(12)
    end

    ['0x1A', '0b11', '3.14', '12.0', '1e3', '', '1__0', '_1', 'abc', ' '].each do |input|
      it "refuses #{input.inspect} with the base-10 message and no echo" do
        expect { type.coerce(input) }
          .to raise_error(ArgumentError, 'Integer fields expect a base-10 integer, got a String that is not one')
      end
    end

    it 'names base-N for another radix' do
      expect { type.coerce('zz', base: 16) }
        .to raise_error(ArgumentError, 'Integer fields expect a base-16 integer, got a String that is not one')
    end

    it 'ignores base: for non-strings' do
      expect(type.coerce(12, base: 16)).to eq(12)
    end
  end

  describe 'FS-B61 other input' do
    it 'passes Integers, truncates Float and Rational toward zero' do
      expect(type.coerce(5)).to eq(5)
      expect(type.coerce(12.7)).to eq(12)
      expect(type.coerce(-12.7)).to eq(-12)
      expect(type.coerce(Rational(25, 2))).to eq(12)
    end

    it 'converts BigDecimal and epoch Times' do
      expect(type.coerce(BigDecimal('12.9'))).to eq(12)
      expect(type.coerce(Time.at(100))).to eq(100)
    end

    it 'raises TypeError with a class-only message for unconvertible objects' do
      [:sym, true, [], {}, Object.new].each do |value|
        expect { type.coerce(value) }.to raise_error(TypeError, /\Acan't convert \S+ into Integer\z/)
      end
    end

    it 'refuses non-finite numbers naming the class' do
      expect { type.coerce(Float::NAN) }
        .to raise_error(ArgumentError, 'Integer fields expect a finite number, got a non-finite Float')
      expect { type.coerce(-Float::INFINITY) }
        .to raise_error(ArgumentError, 'Integer fields expect a finite number, got a non-finite Float')
      expect { type.coerce(BigDecimal('NaN')) }
        .to raise_error(ArgumentError, 'Integer fields expect a finite number, got a non-finite BigDecimal')
      expect { type.coerce(BigDecimal('Infinity')) }
        .to raise_error(ArgumentError, 'Integer fields expect a finite number, got a non-finite BigDecimal')
    end

    it 're-raises a RangeError as ArgumentError without the original in the cause chain' do
      expect { type.coerce(Complex(1, 2)) }
        .to raise_error(ArgumentError, 'Integer fields could not read a Complex as a number') { |e| expect(e.cause).to be_nil }
    end
  end

  describe 'FS-B62 decimal size cap' do
    it 'refuses a BigDecimal over 4300 digits quickly' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { type.coerce(BigDecimal('1e10000000')) }
        .to raise_error(ArgumentError, 'Integer fields read a decimal of at most 4300 digits, got a larger BigDecimal')
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    end

    it 'accepts exactly 4300 digits' do
      expect(type.coerce(BigDecimal('1e4299'))).to eq(10**4299)
    end

    it 'accepts a finite 10**400' do
      expect(type.coerce(BigDecimal('1e400'))).to eq(10**400)
    end
  end

  describe 'FS-B63 strict: true' do
    it 'accepts whole numbers of any numeric kind' do
      [12, 12.0, BigDecimal('12'), Rational(24, 2), Complex(12, 0)].each do |value|
        expect(type.coerce(value, strict: true)).to eq(12)
      end
    end

    it 'refuses fractions with the whole-number message' do
      expect { type.coerce(12.7, strict: true) }
        .to raise_error(ArgumentError, 'Integer fields with strict: true expect a whole number, got a Float that is not one')
      expect { type.coerce(Rational(25, 2), strict: true) }
        .to raise_error(ArgumentError, /expect a whole number, got a Rational that is not one/)
    end

    it 'follows the default rules for Strings' do
      expect(type.coerce('42', strict: true)).to eq(42)
      expect { type.coerce('12.0', strict: true) }.to raise_error(ArgumentError, /base-10 integer/)
      expect { type.coerce('1e3', strict: true) }.to raise_error(ArgumentError, /base-10 integer/)
    end

    it 'refuses a Time and other non-numerics' do
      expect { type.coerce(Time.at(1), strict: true) }.to raise_error(ArgumentError, /whole number, got a Time/)
      expect { type.coerce(Object.new, strict: true) }.to raise_error(ArgumentError, /whole number/)
    end

    it 'still refuses non-finite' do
      expect { type.coerce(Float::INFINITY, strict: true) }.to raise_error(ArgumentError, /non-finite/)
    end
  end
end
