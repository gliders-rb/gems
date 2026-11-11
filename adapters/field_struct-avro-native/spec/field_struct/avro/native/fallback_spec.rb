# frozen_string_literal: true

RSpec.describe FieldStruct::Avro::Native, 'fallback to the pure path' do
  include Paths

  # Each Class is defined fresh per example so the cache rules are exercised from cold.
  def kiln(&)
    klass = Class.new(FieldStruct::Base, &)
    stub_const('Kiln', klass)
    klass
  end

  def expect_fallback(struct, raises: true)
    entry = FieldStruct::Avro::Cache.reader(struct.class, :avro, :micros)
    datum = FieldStruct::Avro.to_datum(struct)
    expect(native_write(entry.parsed, datum)).to be_nil

    native = outcome { FieldStruct::Avro.encode(struct) }
    expect(native).to eq(outcome { pure_encode(struct) })
    expect(native.first).to eq(raises ? :raised : :ok)
    native
  end

  it 'leaves an invalid instance to the pure path, which names it (AV-B33)' do
    struct = kiln { required :count, :integer }.new(count: 'many')
    _, klass, message = expect_fallback(struct)
    expect([klass,
            message]).to eq([ArgumentError, "FieldStruct::Avro can't encode an invalid Kiln: #{struct.errors.full_messages.join('; ')}"])
  end

  it 'leaves a decimal past its precision to the avro gem (AV-B34)' do
    struct = kiln { required :honey, :big_decimal, round: 2 }.new(honey: BigDecimal("1#{'0' * 40}"))
    expect(expect_fallback(struct)[1]).to eq(RangeError)
  end

  it 'leaves a decimal with more places than its scale to the avro gem (AV-B34)' do
    struct = kiln { required :ratio, :big_decimal, avro: { scale: 2 } }.new(ratio: BigDecimal('1.234'))
    expect(expect_fallback(struct)[1..]).to eq([RangeError, 'Rounding necessary'])
  end

  it 'leaves a zero at scale 0 to the avro gem, which refuses it' do
    struct = kiln { required :frames, :big_decimal, round: 0 }.new(frames: 0)
    expect(expect_fallback(struct)[1..]).to eq([RangeError, 'Rounding necessary'])
  end

  it 'leaves an integer past 64 bits to the avro gem (AV-B35)' do
    struct = kiln { required :count, :integer }.new(count: 2**64)
    expect(expect_fallback(struct)[1]).to eq(Avro::IO::AvroTypeError)
  end

  it 'leaves an integer past 32 bits in an int override to the avro gem' do
    struct = kiln { required :count, :integer, avro: { type: 'int' } }.new(count: 2**31)
    expect(expect_fallback(struct)[1]).to eq(Avro::IO::AvroTypeError)
  end

  it 'leaves a BigDecimal in a string override to the avro gem (AV-B34)' do
    struct = kiln { required :honey, :big_decimal, avro: { type: 'string' } }.new(honey: BigDecimal('1.5'))
    expect(expect_fallback(struct)[1]).to eq(Avro::IO::AvroTypeError)
  end

  it 'leaves a binary String in a string field to the avro gem, which cannot transcode it' do
    struct = kiln { required :name, :string }.new(name: "\xFF".b)
    expect(expect_fallback(struct)[1]).to eq(Encoding::UndefinedConversionError)
  end

  it 'leaves a non-UTF-8 String to the avro gem, which transcodes it' do
    struct = kiln { required :name, :string }.new(name: 'miel dorée'.encode('ISO-8859-1'))
    expect(expect_fallback(struct, raises: false).last).to eq("\x16miel dor\xC3\xA9e".b)
  end

  it 'leaves an Integer in a double field to the avro gem, which writes it as a double' do
    struct = kiln { required :weight, :value, avro: { type: 'double' } }.new(weight: 3)
    expect(expect_fallback(struct, raises: false).last).to eq([3.0].pack('E'))
  end

  it 'never sees a time with too much precision: the datum step refuses it first (AV-B21)' do
    struct = kiln { required :at, :time }.new(at: Time.at(0, 1, :nsec).utc)
    native = outcome { FieldStruct::Avro.encode(struct) }
    expect(native).to eq(outcome { pure_encode(struct) })
    expect(native[1..]).to eq([ArgumentError, 'FieldStruct::Avro: Kiln#at is 1970-01-01T00:00:00.000000001Z, which has more ' \
                                              'precision than timestamp-micros; round it, or use timestamp: :nanos'])
  end

  it 'leaves a schema shape it does not cover (fixed) to the pure path' do
    struct = kiln { required :tag, :string, avro: { type: { type: 'fixed', name: 'Tag', size: 2 } } }.new(tag: 'ab')
    expect(expect_fallback(struct, raises: false).last).to eq('ab')
  end
end
