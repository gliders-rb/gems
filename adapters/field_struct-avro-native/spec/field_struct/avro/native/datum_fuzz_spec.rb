# frozen_string_literal: true

RSpec.describe FieldStruct::Avro::Native, 'on random schemas and datums' do
  include Paths

  let(:fuzz) { SchemaFuzz.new }

  it 'writes exactly the pure bytes whenever it writes, and leaves every datum the pure path rejects to it' do
    tally = Hash.new(0)
    1500.times do
      json = fuzz.schema
      schema = begin
        Avro::Schema.parse(JSON.dump(json))
      rescue Avro::SchemaParseError
        next tally[:schema_refused] += 1
      end

      6.times do
        datum = fuzz.datum(schema)
        native = native_write(schema, datum)
        pure = outcome { pure_write(schema, datum) }
        if native
          tally[:native] += 1
          expect(pure).to eq([:ok, native]), -> { "schema #{JSON.dump(json)}\ndatum #{datum.inspect}\npure #{pure.inspect}" }
        else
          tally[pure.first == :ok ? :fell_back_ok : :fell_back_raised] += 1
        end
      end
    end

    # The run is only meaningful when the native path took most datums and the fallback saw both outcomes.
    expect(tally[:native]).to be > 4000
    expect(tally[:fell_back_raised]).to be > 50
    expect(tally[:fell_back_ok]).to be > 20
  end

  it 'reads its own bytes back with the avro gem' do
    500.times do
      json = fuzz.record(0)
      schema = Avro::Schema.parse(JSON.dump(json))
      datum = fuzz.datum(schema)
      bytes = native_write(schema, datum) or next

      decoder = Avro::IO::BinaryDecoder.new(StringIO.new(bytes))
      read = Avro::IO::DatumReader.new(schema).read(decoder)
      expect(pure_write(schema, read)).to eq(bytes)
    end
  end
end
