# frozen_string_literal: true

RSpec.describe 'A required nullable field in Avro (AV-B7)' do
  let(:avro) { FieldStruct::Avro }

  let(:sighting) do
    define_struct('Sighting') do
      required :beacon, :string
      required :dimmed_at, :date, nullable: true
      required :lamp, :string, nullable: true, default: 'amber'
    end
  end

  it 'is a nullable union with no default, and with its default when it has one' do
    fields = avro.schema(sighting)['fields']
    expect(fields[1]).to eq('name' => 'dimmed_at', 'type' => ['null', { 'type' => 'int', 'logicalType' => 'date' }])
    expect(fields[2]).to eq('name' => 'lamp', 'type' => %w[string null], 'default' => 'amber')
  end

  it 'encodes and decodes a given nil' do
    bytes = avro.encode(sighting.new(beacon: 'North Pier', dimmed_at: nil, lamp: nil))
    back = avro.decode(sighting, bytes)
    expect([back.beacon, back.dimmed_at, back.lamp, back.valid?]).to eq(['North Pier', nil, nil, true])
  end
end
