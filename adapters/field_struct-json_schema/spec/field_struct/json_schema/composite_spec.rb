# frozen_string_literal: true

RSpec.describe FieldStruct::JSONSchema, 'composites' do
  describe 'JS-B11: arrays' do
    it 'wraps the element schema as nullable items' do
      klass = struct do
        required :tags, :array, of: :string
        optional :counts, :array, of: :integer
        optional :colors, :array, of: :string, element: { enum: %w[red green] }
      end
      expect(property(klass, :tags)).to eq('type' => 'array', 'items' => { 'type' => %w[string null] })
      expect(property(klass, :counts)).to eq('type' => %w[array null], 'items' => { 'type' => %w[integer null] })
      expect(property(klass, :colors)['items']).to eq('type' => %w[string null], 'enum' => ['red', 'green', nil])
    end

    it 'leaves out items when the element type is unknown (an array of unions)' do
      union = Class.new(FieldStruct::Types::Union)
      klass = struct { required :mixed, :array, of: union }
      expect(property(klass, :mixed)).to eq('type' => 'array')
    end

    it 'treats an array of arrays as nullable inner arrays without items' do
      klass = struct { optional :grid, :array, of: :array }
      expect(property(klass, :grid)).to eq('type' => %w[array null], 'items' => { 'type' => %w[array null] })
    end

    it 'JS-B22: puts no format on uuid elements unless element: gives one' do
      klass = struct do
        required :ids, :array, of: :uuid
        required :codes, :array, of: :uuid, element: { format: /\A[A-Z]{3}\z/ }
      end
      expect(property(klass, :ids)['items']).to eq('type' => %w[string null])
      expect(property(klass, :codes)['items']).to include('type' => %w[string null])
    end
  end

  describe 'JS-B14: unions' do
    it 'lists distinct member schemas under anyOf' do
      klass = struct do
        required :v, :union, of: %i[string integer]
        required :same, :union, of: %i[string immutable_string]
        optional :opt, :union, of: %i[string integer]
      end
      expect(property(klass, :v)).to eq('anyOf' => [{ 'type' => 'string' }, { 'type' => 'integer' }])
      expect(property(klass, :same)).to eq('anyOf' => [{ 'type' => 'string' }])
      expect(property(klass, :opt)).to eq('anyOf' => [{ 'type' => 'string' }, { 'type' => 'integer' }, { 'type' => 'null' }])
    end

    it 'is unconstrained when any member is' do
      klass = struct { required :v, :union, of: %i[string value] }
      expect(property(klass, :v)).to eq({})
    end

    it 'gives members no options, so a :uuid member has no format' do
      klass = struct { required :v, :union, of: %i[uuid integer] }
      expect(property(klass, :v)['anyOf'].first).to eq('type' => 'string')
    end

    it 'references nested structs from union members' do
      stub_const('UWing', struct { required :floor, :string })
      klass = struct { required :v, :union, of: [UWing, :integer] }
      expect(property(klass, :v)['anyOf']).to eq([{ '$ref' => '#/$defs/UWing' }, { 'type' => 'integer' }])
    end
  end

  describe 'JS-B15: nested structs' do
    before do
      stub_const('Wing', struct { required :floor, :string })
      stub_const('Exhibit', struct { required :name, :string })
      stub_const('Curator', struct do
        required :vault, Wing
        optional :work, Wing
        optional :exhibits, :array, of: Exhibit
      end)
    end

    it 'references named structs and defines them once under $defs in first-reference order' do
      schema = described_class.generate(Curator)
      expect(schema['properties']['vault']).to eq('$ref' => '#/$defs/Wing')
      expect(schema['properties']['work']).to eq('anyOf' => [{ '$ref' => '#/$defs/Wing' }, { 'type' => 'null' }])
      expect(schema['properties']['exhibits']['items']).to eq('anyOf' => [{ '$ref' => '#/$defs/Exhibit' }, { 'type' => 'null' }])
      expect(schema['$defs'].keys).to eq(%w[Wing Exhibit])
      expect(schema['$defs']['Wing']).to eq(
        'title' => 'Wing', 'type' => 'object', 'properties' => { 'floor' => { 'type' => 'string' } }, 'required' => ['floor']
      )
      expect(schema.keys.last).to eq('$defs')
    end

    it 'validates real to_json output' do
      schema = described_class.generate(Curator)
      curator = Curator.new(vault: { floor: 'A' }, exhibits: [{ name: 'Sphinx' }])
      expect(valid_json?(schema, curator)).to be(true)
      expect(valid_value?(schema, Oj.load(curator.to_json).merge('vault' => { 'floor' => 1 }))).to be(false)
      expect(valid_value?(schema, Oj.load(curator.to_json).merge('exhibits' => [{ 'name' => 3 }]))).to be(false)
    end

    it 'inlines an anonymous struct, without title or $schema' do
      inner = struct { required :x, :integer }
      klass = struct { required :inner, inner }
      schema = described_class.generate(klass)
      expect(property(klass, :inner)).to eq('type' => 'object', 'properties' => { 'x' => { 'type' => 'integer' } }, 'required' => ['x'])
      expect(schema).not_to have_key('$defs')
    end

    it 'inlines a struct named under an anonymous module' do
      mod = Module.new
      mod.const_set(:Inner, struct { required :x, :integer })
      expect(mod::Inner.name).to include('#<')
      klass = struct { required :inner, mod::Inner }
      expect(property(klass, :inner)).not_to have_key('$ref')
    end

    it 'refers to the root class as # and terminates on cycles' do
      stub_const('Node', Class.new(FieldStruct::Base))
      Node.class_eval do
        required :value, :integer
        optional :next_node, Node
      end
      schema = described_class.generate(Node)
      expect(schema['properties']['next_node']).to eq('anyOf' => [{ '$ref' => '#' }, { 'type' => 'null' }])
      expect(schema).not_to have_key('$defs')
    end

    it 'reserves the $defs slot so a named cycle through another struct terminates' do
      stub_const('CycA', Class.new(FieldStruct::Base))
      stub_const('CycB', Class.new(FieldStruct::Base))
      CycA.class_eval { optional :b, CycB }
      CycB.class_eval { optional :a, CycA }
      schema = described_class.generate(CycA)
      expect(schema['properties']['b']['anyOf'].first).to eq('$ref' => '#/$defs/CycB')
      expect(schema['$defs']['CycB']['properties']['a']['anyOf'].first).to eq('$ref' => '#')
    end

    it 'refuses a recursive anonymous struct' do
      chain = Class.new(FieldStruct::Base)
      chain.class_eval { optional :next_link, chain }
      expect { described_class.generate(chain) }
        .to raise_error(ArgumentError, "FieldStruct::JSONSchema.generate(#{chain.inspect}) cannot describe a recursive anonymous " \
                                       'struct; assign it to a constant')
    end

    it 'JS-B16: puts additionalProperties false on nested objects by their own class' do
      stub_const('StrictInner', struct do
        unknown_attributes :raise
        required :x, :integer
      end)
      stub_const('LooseOuter', struct { required :inner, StrictInner })
      schema = described_class.generate(LooseOuter)
      expect(schema).not_to have_key('additionalProperties')
      expect(schema['$defs']['StrictInner']['additionalProperties']).to be(false)
    end

    it 'JS-B17: names every struct in the tree by its own serialization mapping' do
      stub_const('SWing', struct do
        required :room_code, :string
        serialize :json, room_code: 'zip'
      end)
      stub_const('SCurator', struct do
        required :vault, SWing
        serialize :json, vault: 'house'
      end)
      schema = described_class.generate(SCurator)
      expect(schema['properties'].keys).to eq(['house'])
      expect(schema['$defs']['SWing']['properties'].keys).to eq(['zip'])
    end
  end
end
