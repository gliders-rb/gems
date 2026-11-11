# frozen_string_literal: true

module IntrospectionFixtures
  class Bed < FieldStruct::Base
    optional :habitat, :string
  end

  class Gardener < FieldStruct::Base
    required :name, :string
    optional :beds, :array, of: Bed
    optional :level, :integer, in: 1..5
    serialize :json, beds: 'plots'
  end
end

RSpec.describe FieldStruct::Introspection do
  let(:bed) { IntrospectionFixtures::Bed }
  let(:gardener) { IntrospectionFixtures::Gardener }
  let(:types) { FieldStruct::Types }

  def klass(&block)
    Class.new(FieldStruct::Base, &block)
  end

  describe 'FS-B140 surface' do
    it 'defines exactly the five nested classes and the module functions' do
      nested = described_class.constants.map { |c| described_class.const_get(c) }.grep(Class).map { |c| c.name.split('::').last }
      expect(nested).to contain_exactly('Property', 'ScalarNode', 'ArrayNode', 'UnionNode', 'StructNode')
      expect(described_class).to respond_to(:properties, :node, :named?)
    end

    it 'ships no JSON Schema in core' do
      expect(FieldStruct.const_defined?(:JSONSchema)).to be(false)
      expect(FieldStruct::Base).not_to respond_to(:to_json_schema)
      expect(types::Base.instance_methods).not_to include(:json_schema)
      if types::Base.respond_to?(:descendants)
        types::Base.descendants.each do |type|
          expect(type.instance_methods).not_to include(:json_schema)
        end
      end
      expect(FieldStruct.constants.grep(/json_?schema/i)).to be_empty
    end
  end

  describe '.properties' do
    it 'FS-B141 gives one Property per field in declaration order, inherited included' do
      child = Class.new(gardener) { optional :extra, :string }
      expect(described_class.properties(child).map { |p| p.field.name }).to eq(%i[name beds level extra])
      expect(described_class.properties(klass)).to eq([])
    end

    it 'FS-B141 returns a new Array of new objects each call' do
      a = described_class.properties(gardener)
      b = described_class.properties(gardener)
      expect(a).not_to equal(b)
      expect(a.first).not_to equal(b.first)
    end

    it 'FS-B141 accepts a String serialization' do
      expect(described_class.properties(gardener, serialization: 'json').map(&:key)).to eq(%w[name plots level])
    end

    it 'FS-B142 keys use the mapping, always Strings' do
      name, beds = described_class.properties(gardener)
      expect([name.key, beds.key]).to eq(%w[name plots])
      mapped = klass do
        required :total, :integer
        serialize :json, total: :grand_total
      end
      expect(described_class.properties(mapped).first.key).to eq('grand_total')
    end

    it 'FS-B142 keeps names for an undeclared format' do
      mapped = klass do
        required :total, :integer
        serialize :json, total: :grand_total
      end
      expect(described_class.properties(mapped, serialization: :csv).first.key).to eq('total')
    end

    it 'FS-B143 Property#field is the class own Field and node comes from the type instance and options' do
      name, beds = described_class.properties(gardener)
      expect(name.field).to equal(gardener.metadata[:name])
      expect(name.node).to be_a(described_class::ScalarNode)
      expect(beds.node).to be_a(described_class::ArrayNode)
    end
  end

  describe '.node' do
    it 'FS-B143 dispatches on the type instance' do
      expect(described_class.node(types::Array.new)).to be_a(described_class::ArrayNode)
      expect(described_class.node(types::Union.new([types::String.new, types::Integer.new]))).to be_a(described_class::UnionNode)
      expect(described_class.node(types::Nested.new(bed))).to be_a(described_class::StructNode)
    end

    it 'FS-B143 gives ScalarNode for scalars, :value, :binary, custom types and non-type objects' do
      custom = Class.new(types::Base)
      [types::String, types::Value, types::Binary, types::Boolean, custom].each do |type|
        expect(described_class.node(type.new)).to be_a(described_class::ScalarNode)
      end
      expect(described_class.node(Object.new)).to be_a(described_class::ScalarNode)
      expect(described_class.node(:oops)).to be_a(described_class::ScalarNode)
    end

    it 'FS-B143 Property#node equals node(type_instance, options)' do
      field = gardener.metadata[:level]
      node = described_class.properties(gardener).last.node
      expect(node.type).to equal(field.type_instance)
      expect(node.options).to equal(field.options)
    end
  end

  describe 'ScalarNode' do
    it 'FS-B144 keeps the field own type instance and options Hash' do
      k = klass { optional :level, :integer, in: 1..5 }
      node = described_class.properties(k).first.node
      expect(node.type).to be_a(types::Integer)
      expect(node.type).to equal(k.metadata[:level].type_instance)
      expect(node.options).to eq(in: 1..5)
      expect(node.options).to equal(k.metadata[:level].options)
      expect(node.options).to be_frozen
    end

    it 'FS-B144 defaults options to an empty Hash' do
      expect(described_class.node(types::String.new).options).to eq({})
    end

    it 'FS-B149 is frozen' do
      expect(described_class::ScalarNode.new(types::String.new, {})).to be_frozen
    end
  end

  describe 'ArrayNode' do
    def element_of(declare)
      k = klass(&declare)
      described_class.properties(k).first.node
    end

    it 'FS-B145 keeps the Types::Array instance and the field options, including of_type and element' do
      node = element_of(proc { optional :a, :array, of: :string, element: { strict: true } })
      expect(node.type).to be_a(types::Array)
      expect(node.options).to eq(of_type: types::String, element: { strict: true })
    end

    it 'FS-B146 builds a ScalarNode element from a type class with empty options' do
      element = element_of(proc { optional :a, :array, of: :string }).element
      expect(element).to be_a(described_class::ScalarNode)
      expect(element.type).to be_a(types::String)
      expect(element.options).to eq({})
    end

    it 'FS-B146 passes element: options to a scalar element' do
      element = element_of(proc { optional :a, :array, of: :string, element: { strict: true } }).element
      expect(element.options).to eq(strict: true)
    end

    it 'FS-B146 gives a StructNode for struct elements' do
      bd = bed
      element = element_of(proc { optional :a, :array, of: bd }).element
      expect(element).to be_a(described_class::StructNode)
      expect(element.klass).to equal(bed)
    end

    it 'FS-B146 gives nil for unions and for a missing of_type' do
      expect(element_of(proc { optional :a, :array, of: :union }).element).to be_nil
      expect(described_class.node(types::Array.new, {}).element).to be_nil
      expect(described_class.node(types::Array.new, of_type: types::Union).element).to be_nil
      sub = Class.new(types::Union)
      expect(described_class.node(types::Array.new, of_type: sub).element).to be_nil
    end

    it 'FS-B146 gives an ArrayNode with no element for an array of arrays' do
      node = element_of(proc { optional :a, :array, of: :array })
      expect(node.element).to be_a(described_class::ArrayNode)
      expect(node.element.options).to eq({})
      expect(node.element.element).to be_nil
    end

    it 'FS-B145 builds the element once, lazily, and returns the same object' do
      builds = 0
      node = described_class::ArrayNode.new(types::Array.new, {}, lambda {
        builds += 1
        described_class.node(types::String.new)
      })
      expect(builds).to eq(0)
      first = node.element
      expect(node.element).to equal(first)
      expect(builds).to eq(1)
    end

    it 'FS-B145 returns the same nil on later reads without rebuilding' do
      builds = 0
      node = described_class::ArrayNode.new(types::Array.new, {}, -> { (builds += 1) && nil })
      expect([node.element, node.element]).to eq([nil, nil])
      expect(builds).to eq(1)
    end

    it 'FS-B145 never instantiates the element type unless element is read' do
      custom = Class.new(types::String) do
        define_singleton_method(:new) { |*| raise 'instantiated' }
      end
      node = described_class.node(types::Array.new, of_type: custom)
      expect { node }.not_to raise_error
      expect { node.element }.to raise_error('instantiated')
    end

    it 'FS-B149 is frozen even before and after the element is read' do
      node = element_of(proc { optional :a, :array, of: :string })
      expect(node).to be_frozen
      node.element
      expect(node).to be_frozen
    end
  end

  describe 'UnionNode' do
    it 'FS-B147 has one node per member, in order, with empty options' do
      bd = bed
      k = klass { optional :u, :union, of: [:string, bd, :integer] }
      node = described_class.properties(k).first.node
      expect(node.type).to be_a(types::Union)
      expect(node.members.map(&:class)).to eq([described_class::ScalarNode, described_class::StructNode, described_class::ScalarNode])
      expect([node.members[0], node.members[2]].map(&:options)).to all(eq({}))
      expect(node.members[1].klass).to equal(bed)
      expect(node.members).to be_frozen
      expect(node).to be_frozen
    end
  end

  describe 'StructNode' do
    it 'FS-B148 is a reference to the struct class and does not expand it' do
      k = klass { optional :border, IntrospectionFixtures::Bed }
      node = described_class.properties(k).first.node
      expect(node).to be_a(described_class::StructNode)
      expect(node.type).to be_a(types::Nested)
      expect(node.klass).to equal(bed)
      expect(node).to be_frozen
    end

    it 'FS-B148 a self-referential struct does not loop' do
      node_class = Class.new(FieldStruct::Base)
      node_class.optional :child, node_class
      expect(described_class.properties(node_class).first.node.klass).to equal(node_class)
    end
  end

  describe 'immutability and policy' do
    it 'FS-B149 freezes Property' do
      expect(described_class.properties(gardener)).to all(be_frozen)
    end

    it 'FS-B149 leaves the options contents as the live objects' do
      k = klass { optional :level, :string, enum: %w[a b] }
      node = described_class.properties(k).first.node
      expect(node.options[:enum]).to equal(k.metadata[:level].options[:enum])
    end

    it 'FS-B151 reports pass-through options verbatim without judging them' do
      k = klass { optional :id, :integer, avro: { doc: 'the id' }, json_schema: { format: 'int64' } }
      node = described_class.properties(k).first.node
      expect(node.options).to eq(avro: { doc: 'the id' }, json_schema: { format: 'int64' })
    end

    it 'FS-B152 changes nothing on the class and shows a redeclared field next time' do
      k = klass { optional :a, :string }
      before = k.metadata.to_a
      first = described_class.properties(k).first
      expect(k.metadata.to_a).to eq(before)
      expect(k.new(a: 1).a).to eq('1')
      k.optional :a, :integer
      again = described_class.properties(k).first
      expect(again.field).not_to equal(first.field)
      expect(again.node.type).to be_a(types::Integer)
    end
  end

  describe '.named?' do
    it 'FS-B150 is true for named classes and false for anonymous ones' do
      expect(described_class.named?(bed)).to be(true)
      expect(described_class.named?(Class.new)).to be(false)
    end

    it 'FS-B150 is false for a class under an anonymous module' do
      mod = Module.new
      mod.const_set(:Addr, Class.new(FieldStruct::Base))
      expect(mod::Addr.name).to include('#<')
      expect(described_class.named?(mod::Addr)).to be(false)
    end
  end

  it 'the documented example works' do
    name, beds = described_class.properties(gardener)
    expect(name.key).to eq('name')
    expect(name.field.required?).to be(true)
    expect(beds.key).to eq('plots')
    expect(beds.node.element.klass == bed).to be(true)
  end
end
