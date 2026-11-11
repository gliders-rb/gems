# frozen_string_literal: true

RSpec.describe FieldStruct::Avro::Native, 'on generated structs' do
  include Paths

  it 'is enabled once required' do
    expect(described_class.enabled?).to be(true)
  end

  %i[micros nanos millis].each do |timestamp|
    it "encodes 1000 random hives to the pure bytes with timestamp: #{timestamp.inspect}, and they read back" do
      native_hits = 0
      outcomes = Hash.new(0)
      1000.times do
        hive = Apiary::Hive.new(Apiary::Values.hive(timestamp))
        expect(hive).to be_valid, -> { hive.errors.full_messages.inspect }

        native = outcome { FieldStruct::Avro.encode(hive, timestamp: timestamp) }
        expect(native).to eq(outcome { pure_encode(hive, timestamp: timestamp) })
        outcomes[native.first] += 1
        next unless native.first == :ok

        entry = FieldStruct::Avro::Cache.reader(Apiary::Hive, :avro, timestamp)
        native_hits += 1 if native_write(entry.parsed, FieldStruct::Avro.to_datum(hive, timestamp: timestamp))
        back = FieldStruct::Avro.decode(Apiary::Hive, native.last, timestamp: timestamp)
        expect(FieldStruct::Avro.encode(back, timestamp: timestamp)).to eq(native.last)
      end

      expect(outcomes).to eq(ok: 1000)
      expect(native_hits).to eq(outcomes[:ok])
    end
  end

  it 'writes a deep recursive struct the way the pure path does' do
    yard = Apiary::Yard.new(Apiary::Values.yard(6))
    expect(FieldStruct::Avro.encode(yard)).to eq(pure_encode(yard))
  end
end
