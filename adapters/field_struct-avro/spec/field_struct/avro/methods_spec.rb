# frozen_string_literal: true

RSpec.describe FieldStruct::Avro::Methods do
  let(:avro) { FieldStruct::Avro }
  let(:klass) do
    define_struct('Mixed') do
      include FieldStruct::Avro::Methods

      required :id, :integer
      required :at, :time
      serialize :kafka, id: 'key'
    end
  end

  it 'adds to_avro_schema, to_avro and from_avro, delegating with the options' do
    expect(klass.to_avro_schema).to eq(avro.schema(klass))
    options = { serialization: :kafka, timestamp: :nanos }
    expect(klass.to_avro_schema(**options)).to eq(avro.schema(klass, **options))
    instance = klass.new(id: 1, at: Time.utc(2026, 1, 1, 0, 0, 0, 1))
    expect(instance.to_avro(timestamp: :nanos)).to eq(avro.encode(instance, timestamp: :nanos))
    expect(klass.from_avro(instance.to_avro, timestamp: :micros)).to eq(instance)
    expect(klass.from_avro(instance.to_avro(serialization: :kafka), serialization: :kafka)).to eq(instance)
  end

  it 'passes writer_schema: through from_avro' do
    older = define_struct('Rd::Mixed2') { required :id, :integer }
    newer = define_struct('Rd::Mixed3') do
      include FieldStruct::Avro::Methods

      required :id, :integer
      optional :note, :string
    end
    writer = avro.schema(older).merge('name' => 'Mixed3')
    expect(newer.from_avro(avro.encode(older.new(id: 5)), writer_schema: writer).note).to be_nil
  end

  it 'adds nothing to a class that does not include it' do
    other = define_struct('NotMixed') { required :id, :integer }
    expect(other).not_to respond_to(:from_avro)
  end
end
