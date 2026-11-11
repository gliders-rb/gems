# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'declaring fields' do
  def named(name, parent = FieldStruct::Base, &block)
    klass = stub_const(name, Class.new(parent))
    klass.class_eval(&block) if block
    klass
  end

  describe 'FS-B1 return values and required-ness' do
    it 'returns the class Metadata, with the new Field at metadata[name]' do
      klass = Class.new(described_class)
      result = klass.required :a, :string
      expect(result).to equal(klass.metadata)
      expect(klass.metadata[:a]).to be_a(FieldStruct::Field)
    end

    it 'sets required-ness by macro and lets required/optional override required:' do
      klass = Class.new(described_class)
      klass.required :a, :string
      klass.optional :b, :string
      klass.field :c, :string
      klass.field :d, :string, required: true
      klass.optional :e, :string, required: true
      klass.required :f, :string, required: false
      flags = klass.metadata.to_h { |f| [f.name, f.required?] }
      expect(flags).to eq(a: true, b: false, c: false, d: true, e: false, f: true)
    end
  end

  describe 'FS-B2 type argument' do
    it 'accepts Symbol and String names, aliases, and a type class used directly' do
      custom = Class.new(FieldStruct::Types::Base) do
        def coerce(value, **) = value
        def ruby_type = Object
      end
      klass = Class.new(described_class)
      klass.field :a, :string
      klass.field :b, 'integer'
      klass.field :c, :decimal
      klass.field :d, custom
      expect(klass.metadata[:a].type).to equal(FieldStruct::Types::String)
      expect(klass.metadata[:b].type).to equal(FieldStruct::Types::Integer)
      expect(klass.metadata[:c].type).to equal(FieldStruct::Types::BigDecimal)
      expect(klass.metadata[:d].type).to equal(custom)
      expect(klass.metadata[:d].type_instance).to be_a(custom)
    end

    it 'refuses a class that is not a type' do
      expect { Class.new(described_class).field(:a, Object) }.to raise_error(ArgumentError, /not a FieldStruct type/)
    end
  end

  describe 'FS-B3 / FS-B4 accessors and names' do
    it 'defines reader and writer, normalizing names to Symbols' do
      klass = Class.new(described_class)
      klass.field 'height', :integer
      expect(klass.metadata.names).to eq([:height])
      instance = klass.new
      instance.height = '30'
      expect(instance.height).to eq(30)
    end

    it 'keeps the original position when a field is redeclared, in the class and a subclass' do
      parent = Class.new(described_class)
      parent.field :a, :string
      parent.field :b, :string
      parent.field :a, :integer
      expect(parent.attribute_names).to eq(%i[a b])
      expect(parent.metadata[:a].type).to equal(FieldStruct::Types::Integer)
      child = Class.new(parent)
      child.field :b, :integer
      expect(child.attribute_names).to eq(%i[a b])
      expect(child.new(b: '4').b).to eq(4)
    end

    it 'lets a subclass override the reader and call super' do
      klass = Class.new(described_class) do
        field :a, :string
        def a = "<#{super}>"
      end
      expect(klass.new(a: 'x').a).to eq('<x>')
    end
  end

  describe 'FS-B5 namespace registries' do
    let(:accession) do
      Class.new(FieldStruct::Types::Base) do
        def coerce(value, **) = value&.to_s&.delete('-')
        def ruby_type = String
      end
    end

    before do
      type = accession
      stub_const('Garden', Module.new)
      Garden.define_singleton_method(:field_types) { @field_types ||= FieldStruct.new_registry { register :accession, type } }
      stub_const('Garden::Catalog', Module.new)
    end

    it 'resolves names through the containing module, falling back to the base registry' do
      plant = stub_const('Garden::Catalog::Plant', Class.new(described_class))
      plant.required :accession, :accession
      plant.required :species, :string
      expect(plant.new(accession: '1-2').accession).to eq('12')
      expect(plant.metadata[:species].type).to equal(FieldStruct::Types::String)
    end

    it 'prefers the nearest module that has field_types' do
      near = Class.new(FieldStruct::Types::Base) do
        def coerce(value, **) = "near #{value}"
        def ruby_type = String
      end
      Garden::Catalog.define_singleton_method(:field_types) do
        @field_types ||= FieldStruct.new_registry { register :accession, near }
      end
      plant = stub_const('Garden::Catalog::Plant', Class.new(described_class))
      plant.field :accession, :accession
      expect(plant.new(accession: 'x').accession).to eq('near x')
    end

    it 'does not consult the class itself or unrelated namespaces' do
      outside = Class.new(described_class)
      expect { outside.field :accession, :accession }.to raise_error(KeyError)
      stub_const('Garden::Registry', Class.new(described_class))
      expect { Garden::Registry.field :accession, :accession }.not_to raise_error
    end

    it 'uses the base registry for anonymous classes and for classes under an anonymous module' do
      mod = Module.new
      mod.const_set(:Addr, Class.new(described_class))
      expect(mod::Addr.name).to include('#<')
      expect { mod::Addr.field :a, :string }.not_to raise_error
      expect { Class.new(described_class).field :a, :string }.not_to raise_error
    end

    it 'exposes resolve_type' do
      plant = stub_const('Garden::Plant', Class.new(described_class))
      expect(plant.resolve_type(:accession)).to equal(accession)
      expect(plant.resolve_type('string')).to equal(FieldStruct::Types::String)
    end
  end

  describe 'FS-B6 unknown type names' do
    it 'raises KeyError at declaration' do
      expect { Class.new(described_class).field(:a, :nope) }
        .to raise_error(KeyError, 'no FieldStruct type registered for :nope')
    end
  end

  describe 'FS-B10 / FS-B11 / FS-B15 options' do
    it 'stores pass-through options verbatim and removes universal options from options' do
      klass = Class.new(described_class)
      klass.optional :id, :integer, avro_doc: 'the id', description: 'Id', default: 1, sensitive: true,
                                    coercion_policy: :replace, rbs_type: '::Integer', in: 1..9
      field = klass.metadata[:id]
      expect(field.options).to eq(avro_doc: 'the id', in: 1..9)
      expect(field.options).to be_frozen
      expect(field.description).to eq('Id')
      expect(field.default).to eq(1)
      expect(field.sensitive?).to be(true)
      expect(field.coercion_policy).to eq(:replace)
      expect(field.rbs_type).to eq('::Integer')
    end
  end

  describe 'FS-B12 description / desc' do
    it 'treats them as aliases and refuses both' do
      klass = Class.new(described_class)
      klass.field :a, :string, desc: 'short'
      klass.field :b, :string, description: 'long'
      expect(klass.metadata[:a].description).to eq('short')
      expect(klass.metadata[:b].desc).to eq('long')
      expect { klass.field :c, :string, desc: 'x', description: 'y' }
        .to raise_error(ArgumentError, 'pass either description: or desc:, not both')
    end

    it 'lets a subclass redeclaration replace the description, back to nil' do
      parent = Class.new(described_class)
      parent.field :a, :string, description: 'x'
      child = Class.new(parent)
      child.field :a, :string
      expect(child.metadata[:a].description).to be_nil
      expect(parent.metadata[:a].description).to eq('x')
    end
  end

  describe 'FS-B13 reserved names' do
    it 'refuses Symbol and String names through field, required and optional' do
      klass = Class.new(described_class)
      %i[field required optional].each do |macro|
        expect { klass.public_send(macro, :errors, :string) }.to raise_error(ArgumentError, /\Afield :errors is reserved/)
        expect { klass.public_send(macro, 'errors', :string) }.to raise_error(ArgumentError, /\Afield :errors is reserved/)
      end
    end

    it 'uses the documented message' do
      expect { Class.new(described_class).field(:errors, :string) }.to raise_error(
        ArgumentError,
        'field :errors is reserved: FieldStruct::Base relies on #errors, and a field would shadow it. ' \
        "Pick another name; serialize :json can keep the external key (e.g. serialize :json, errors_field: 'errors')."
      )
    end

    it 'covers the documented list, with and dup included' do
      %i[errors attributes attribute_names assign_attributes as_json to_json to_h to_model model_name inspect hash class
         send public_send freeze instance_variable_set initialize initialize_copy raise with dup deconstruct
         deconstruct_keys].each do |name|
        expect(described_class::RESERVED_FIELD_NAMES).to include(name)
      end
      expect(described_class::RESERVED_FIELD_NAMES).to be_frozen
    end

    it 'covers the private helpers Base calls on instances' do
      helpers = described_class.private_instance_methods(false).grep(/\Afs_/)
      expect(helpers).not_to be_empty
      expect(described_class::RESERVED_FIELD_NAMES).to include(*helpers)
    end

    it 'leaves method, name, type and format legal' do
      klass = Class.new(described_class)
      %i[method name type format].each { |n| expect { klass.field(n, :string) }.not_to raise_error }
    end
  end

  describe 'FS-B16 defaults' do
    it 'stores the raw default and never evaluates it at declaration' do
      calls = 0
      callable = -> { calls += 1 }
      klass = Class.new(described_class)
      klass.field :a, :integer, default: callable
      expect(klass.metadata[:a].default).to equal(callable)
      expect(calls).to eq(0)
    end
  end

  describe 'FS-B17 / FS-B159 (c) inheritance snapshot' do
    it 'copies the parent fields at subclass creation and shares the Field objects' do
      parent = Class.new(described_class)
      parent.field :a, :string
      child = Class.new(parent)
      parent.field :late, :string
      child.field :own, :string
      expect(child.attribute_names).to eq(%i[a own])
      expect(parent.attribute_names).to eq(%i[a late])
      expect(child.metadata[:a]).to equal(parent.metadata[:a])
    end

    it 'lets a child shadow a field with a different type without touching the parent' do
      parent = Class.new(described_class)
      parent.field :a, :string
      child = Class.new(parent)
      child.field :a, :integer
      expect(child.metadata[:a]).not_to equal(parent.metadata[:a])
      expect(child.new(a: '7').a).to eq(7)
      expect(parent.new(a: 7).a).to eq('7')
    end
  end

  describe 'FS-B160 attribute_names' do
    it 'returns a new Array of Symbols each call, on class and instance' do
      klass = Class.new(described_class)
      klass.field :a, :string
      klass.field :b, :string
      expect(klass.attribute_names).to eq(%i[a b])
      expect(klass.attribute_names).not_to equal(klass.attribute_names)
      expect(klass.new.attribute_names).to eq(%i[a b])
      expect(klass.new(zzz: 1).attribute_names).to eq(%i[a b])
    end
  end

  it 'FS-B152 / FS-B159 (b): redeclaring produces a new Field object' do
    klass = Class.new(described_class)
    klass.field :a, :string
    old = klass.metadata[:a]
    klass.field :a, :string
    expect(klass.metadata[:a]).not_to equal(old)
    expect(klass.metadata.to_a).not_to include(old)
  end

  it 'gives every class its own Metadata, empty for Base' do
    expect(described_class.metadata.names).to eq([])
  end
end
