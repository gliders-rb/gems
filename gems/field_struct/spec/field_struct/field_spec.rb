# frozen_string_literal: true

RSpec.describe FieldStruct::Field do
  let(:type) { FieldStruct::Types::Integer }

  def build(**overrides)
    described_class.new(name: :height, type: type, **overrides)
  end

  it 'FS-B155: exposes the documented readers with their defaults' do
    field = build
    expect(field.name).to eq(:height)
    expect(field.type).to equal(type)
    expect(field.type_instance).to be_a(type)
    expect(field.required?).to be(false)
    expect(field.sensitive?).to be(false)
    expect(field.default).to be_nil
    expect(field.options).to eq({})
    expect(field.coercion_policy).to be_nil
    expect(field.description).to be_nil
    expect(field.desc).to be_nil
    expect(field.rbs_type).to be_nil
  end

  it 'FS-B155: stores what it was given' do
    default = -> { 1 }
    field = build(required: true, default: default, coercion_policy: :raise, description: 'Years',
                  rbs_type: '::Integer', sensitive: true, in: 1..5, avro_doc: 'x')
    expect(field.required?).to be(true)
    expect(field.sensitive?).to be(true)
    expect(field.default).to equal(default)
    expect(field.coercion_policy).to eq(:raise)
    expect(field.description).to eq('Years')
    expect(field.desc).to eq('Years')
    expect(field.rbs_type).to eq('::Integer')
    expect(field.options).to eq(in: 1..5, avro_doc: 'x')
    expect(field.options.keys).to eq(%i[in avro_doc])
  end

  it 'FS-B155: normalizes the name to a Symbol' do
    expect(described_class.new(name: 'height', type: type).name).to eq(:height)
  end

  it 'FS-B155: uses a given type_instance, otherwise builds one per field' do
    instance = type.new
    expect(build(type_instance: instance).type_instance).to equal(instance)
    expect(build.type_instance).not_to equal(build.type_instance)
  end

  it 'FS-I17: is frozen and so are its options' do
    field = build(in: 1..5)
    expect(field).to be_frozen
    expect(field.options).to be_frozen
  end

  it 'FS-B156: default nil and no default are indistinguishable; falsy defaults are real' do
    expect(build(default: nil).default).to be_nil
    expect(build(default: false).default).to be(false)
    expect(build(default: 0).default).to eq(0)
  end

  it 'derives setter_name and ivar_name' do
    field = build
    expect(field.setter_name).to eq(:height=)
    expect(field.ivar_name).to eq(:@height)
  end
end
