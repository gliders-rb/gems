# frozen_string_literal: true

module QuarrySite
  class Grade < FieldStruct::Base
    required :code, :string
    required :hardness, :integer
  end

  class Block < FieldStruct::Base
    coercion_policy :replace
    unknown_attributes :raise
    required :stone, :string, length: 2..20, desc: 'the stone name'
    required :tonnes, :decimal, default: 1
    required :cut_on, :date, nullable: true
    optional :grade, Grade
    optional :tags, :array, of: :string, default: -> { [] }
    serialize :json, cut_on: 'cutOn'
    validate { |block| block.errors.add(:base, 'too heavy to lift') if block.tonnes > 5 }

    def stone = @stone&.upcase
  end
end

RSpec.describe 'FS-B104b: Klass.partial' do
  let(:partial) { QuarrySite::Block.partial }

  it 'is a memoized sibling class named Klass::Partial' do
    expect(partial).to equal(QuarrySite::Block.partial)
    expect(partial).to equal(QuarrySite::Block::Partial)
    expect(partial.superclass).to eq(FieldStruct::Base)
    expect(partial.new(stone: 'slate')).not_to be_a(QuarrySite::Block)
  end

  it 'keeps every field, in order, all optional, with no defaults and nothing nullable' do
    expect(partial.attribute_names).to eq(%i[stone tonnes cut_on grade tags])
    fields = partial.metadata.to_a
    expect(fields.map(&:required?)).to all(be(false))
    expect(fields.map(&:nullable?)).to all(be(false))
    expect(fields.map(&:default)).to all(be_nil)
    expect(partial.new.attributes).to eq(stone: nil, tonnes: nil, cut_on: nil, grade: nil, tags: nil)
  end

  it 'keeps types, options and descriptions, so field checks still apply' do
    record = partial.new(stone: 'x', tonnes: '2.5')
    expect(record.tonnes).to eq(BigDecimal('2.5'))
    expect(record.errors[:stone]).not_to be_empty
    expect(partial.metadata[:stone].description).to eq('the stone name')
  end

  it 'writes only what was given, under the copied mapping' do
    expect(partial.json_omit).to eq(:unset)
    expect(partial.new(cut_on: '2026-04-02').as_json).to eq(cutOn: '2026-04-02')
    expect(partial.new(tonnes: nil).to_json).to eq('{"tonnes":null}')
  end

  it "copies the class's resolved policies" do
    expect([partial.coercion_policy, partial.unknown_attributes]).to eq(%i[replace raise])
    expect { partial.new(colour: 'grey') }.to raise_error(FieldStruct::UnknownAttributeError)
  end

  it 'drops cross-field validators and reader overrides' do
    record = partial.new(stone: 'marble')
    expect(record).to be_valid
    expect(record.stone).to eq('marble')
  end

  it 'leaves nested struct types whole' do
    record = partial.new(grade: { code: 'A' })
    expect(record.grade).to be_a(QuarrySite::Grade)
    expect(record).not_to be_valid
  end

  it 'raises when the class already has its own Partial constant' do
    klass = Class.new(FieldStruct::Base)
    stub_const('QuarrySite::Slab', klass)
    klass.const_set(:Partial, Module.new)
    expect { klass.partial }
      .to raise_error(ArgumentError, 'QuarrySite::Slab::Partial is already defined; QuarrySite::Slab.partial would replace it')
  end

  it 'gives a subclass its own partial' do
    child = Class.new(QuarrySite::Block) { optional :face, :string }
    stub_const('QuarrySite::Paver', child)
    expect(child.partial).not_to equal(partial)
    expect(child.partial.attribute_names.last).to eq(:face)
    expect(child.partial.name).to eq('QuarrySite::Paver::Partial')
  end
end
