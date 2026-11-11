# frozen_string_literal: true

RSpec.describe FieldStruct::Types::BigDecimal do
  subject(:type) { described_class.new }

  it 'FS-B164: ruby_type is BigDecimal' do
    expect(type.ruby_type).to eq(BigDecimal)
  end

  it 'FS-B124: :decimal is the :big_decimal class' do
    expect(FieldStruct.types.lookup(:decimal)).to equal(described_class)
    expect(FieldStruct.types.lookup(:big_decimal)).to equal(described_class)
  end

  it 'declares round and in' do
    expect(described_class.option_schema.keys).to eq(%i[round in])
  end

  it 'FS-B163: default_round is nil' do
    expect(described_class.default_round).to be_nil
  end

  it 'FS-B33: missing only for nil' do
    expect(type.missing?(nil)).to be(true)
    expect(type.missing?(BigDecimal('0'))).to be(false)
  end

  describe 'FS-B66 coercion' do
    it 'passes BigDecimal, reads Float with 15 digits, Integer and Strings' do
      expect(type.coerce(BigDecimal('1.5'))).to eq(BigDecimal('1.5'))
      expect(type.coerce(0.1 + 0.2)).to eq(BigDecimal('0.3'))
      expect(type.coerce(12)).to eq(BigDecimal('12'))
      expect(type.coerce('12.345')).to eq(BigDecimal('12.345'))
      expect(type.coerce(' 1.5 ')).to eq(BigDecimal('1.5'))
      expect(type.coerce('1_000.5')).to eq(BigDecimal('1000.5'))
      expect(type.coerce('1e3')).to eq(BigDecimal('1000'))
      expect(type.coerce('1e3')).to be_a(BigDecimal)
    end

    ['', 'abc', '1.5abc'].each do |input|
      it "refuses #{input.inspect} naming the class" do
        expect { type.coerce(input) }
          .to raise_error(ArgumentError, 'BigDecimal fields could not read a String as a number')
      end
    end

    it 'refuses Rational and plain objects' do
      expect { type.coerce(Rational(1, 2)) }
        .to raise_error(ArgumentError, 'BigDecimal fields could not read a Rational as a number')
      expect { type.coerce(Object.new) }
        .to raise_error(ArgumentError, 'BigDecimal fields could not read an Object as a number')
    end

    it 'refuses non-finite values from any source' do
      expect { type.coerce(Float::NAN) }.to raise_error(ArgumentError, 'BigDecimal fields expect a finite number, got a non-finite Float')
      expect { type.coerce(BigDecimal('NaN')) }.to raise_error(ArgumentError, /non-finite BigDecimal/)
      expect { type.coerce('NaN') }.to raise_error(ArgumentError, /non-finite String/)
      expect { type.coerce('Infinity') }.to raise_error(ArgumentError, /non-finite String/)
    end
  end

  describe 'FS-B67 round:' do
    it 'rounds half up and stays a BigDecimal' do
      expect(type.coerce('12.345', round: 2)).to eq(BigDecimal('12.35'))
      rounded = type.coerce('12.5', round: 0)
      expect(rounded).to eq(BigDecimal('13'))
      expect(rounded).to be_a(BigDecimal)
      expect(type.coerce('-12.5', round: 0)).to eq(BigDecimal('-13'))
    end

    it 'ignores a banker-style BigDecimal.mode set by the host' do
      previous = BigDecimal.mode(BigDecimal::ROUND_MODE)
      BigDecimal.mode(BigDecimal::ROUND_MODE, :banker)
      expect(type.coerce('12.345', round: 2)).to eq(BigDecimal('12.35'))
      expect(type.coerce('12.5', round: 0)).to eq(BigDecimal('13'))
    ensure
      BigDecimal.mode(BigDecimal::ROUND_MODE, previous)
    end

    it 'applies default_round of a subclass when round: is not declared' do
      subclass = Class.new(described_class) { def self.default_round = 1 }
      expect(subclass.new.coerce('1.26')).to eq(BigDecimal('1.3'))
    end
  end
end
