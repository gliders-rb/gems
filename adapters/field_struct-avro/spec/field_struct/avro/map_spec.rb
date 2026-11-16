# frozen_string_literal: true

RSpec.describe 'FieldStruct::Avro maps (AV-B10a)' do
  let(:avro) { FieldStruct::Avro }

  def parses!(klass)
    Avro::Schema.parse(Oj.dump(FieldStruct::Avro.schema(klass), mode: :compat))
  end

  it 'describes a :hash as a map with nullable values' do
    k = define_struct('Beacon') do
      required :ranges, :hash, of: :integer
      optional :lamps, :hash, of: :string
    end
    expect(type_of(k, 'ranges')).to eq('type' => 'map', 'values' => %w[null long])
    expect(type_of(k, 'lamps')).to eq(['null', { 'type' => 'map', 'values' => %w[null string] }])
    parses!(k)
  end

  it 'refuses a map whose value type is unknown' do
    k = define_struct('Foghorn') { optional :tones, :hash, of: :union }
    expect { avro_schema(k) }.to raise_error(
      ArgumentError, "FieldStruct::Avro can't describe Foghorn#tones: a map of arrays or unions records no value type"
    )
  end

  it 'names a struct value record after the field, and round-trips it through bytes' do
    define_struct('Lantern') do
      required :wick_mm, :integer
      optional :lit_at, :time
    end
    k = define_struct('Keeper') { optional :lanterns, :hash, of: Lantern }
    expect(type_of(k, 'lanterns').last['values'].last).to include('type' => 'record', 'name' => 'Lantern')

    lit = Time.utc(2026, 11, 2, 18, 30)
    original = k.new(lanterns: { 'east gallery' => { wick_mm: 12, lit_at: lit }, 'spare' => nil })
    expect(avro.to_datum(original)).to eq('lanterns' => { 'east gallery' => { 'wick_mm' => 12, 'lit_at' => lit }, 'spare' => nil })
    back = avro.decode(k, avro.encode(original))
    expect(back.lanterns['east gallery'].wick_mm).to eq(12)
    expect(back.lanterns['east gallery'].lit_at).to eq(lit)
    expect(back.lanterns).to include('spare' => nil)
  end

  it 'converts scalar values as array items are converted' do
    k = define_struct('Logbook') { required :readings, :hash, of: :big_decimal, element: { round: 2 }, avro: { precision: 8 } }
    back = avro.decode(k, avro.encode(k.new(readings: { 'noon' => '12.5' })))
    expect(back.readings).to eq('noon' => BigDecimal('12.5'))
  end
end
