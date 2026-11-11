# frozen_string_literal: true

RSpec.describe FieldStruct::Avro::Native, 'plan cache' do
  include Paths

  let(:klass) do
    stub_const('Smoker', Class.new(FieldStruct::Base) { required :fuel, :string })
  end

  it 'compiles a schema once, however many times it encodes' do
    allow(FieldStruct::Avro::Native::Compiler).to receive(:call).and_call_original
    5.times { FieldStruct::Avro.encode(klass.new(fuel: 'pine needles')) }
    expect(FieldStruct::Avro::Native::Compiler).to have_received(:call).once
  end

  it 'follows the adapter cache: a field added later reaches the bytes (AV-B52)' do
    before = FieldStruct::Avro.encode(klass.new(fuel: 'burlap'))
    klass.class_eval { optional :lit, :boolean }
    after = klass.new(fuel: 'burlap', lit: true)
    expect(FieldStruct::Avro.encode(after)).to eq(pure_encode(after))
    expect(FieldStruct::Avro.encode(after)).to eq("#{before}\x02\x01".b)
  end

  it 'compiles again after clear_cache (a new parsed schema)' do
    allow(FieldStruct::Avro::Native::Compiler).to receive(:call).and_call_original
    FieldStruct::Avro.encode(klass.new(fuel: 'cotton'))
    FieldStruct::Avro.clear_cache
    FieldStruct::Avro.encode(klass.new(fuel: 'cotton'))
    expect(FieldStruct::Avro::Native::Compiler).to have_received(:call).twice
  end

  it 'remembers a schema it cannot cover and does not try to compile it again' do
    tagged = stub_const('Tagged', Class.new(FieldStruct::Base) do
      required :tag, :string, avro: { type: { type: 'fixed', name: 'T', size: 1 } }
    end)
    allow(FieldStruct::Avro::Native::Compiler).to receive(:call).and_call_original
    3.times { expect(FieldStruct::Avro.encode(tagged.new(tag: 'q'))).to eq('q') }
    expect(FieldStruct::Avro::Native::Compiler).to have_received(:call).once
  end

  it 'gives the same bytes from many threads at once (AV-B57)' do
    structs = Array.new(8) { |i| klass.new(fuel: "twine #{i}") }
    results = structs.map { |s| Thread.new { Array.new(200) { FieldStruct::Avro.encode(s) }.uniq } }.map(&:value)
    expect(results).to eq(structs.map { |s| [pure_encode(s)] })
  end
end
