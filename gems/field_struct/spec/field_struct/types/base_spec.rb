# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Base do
  let(:type) { described_class.new }

  describe 'the NotImplemented contract' do
    it 'coerce raises NotImplementedError naming the class' do
      expect { type.coerce(1) }.to raise_error(NotImplementedError, 'FieldStruct::Types::Base must implement #coerce')
    end

    it 'ruby_type raises NotImplementedError naming the class' do
      expect { type.ruby_type }.to raise_error(NotImplementedError, 'FieldStruct::Types::Base must implement #ruby_type')
    end
  end

  describe 'defaults' do
    it 'missing? is nil?' do
      expect(type.missing?(nil)).to be(true)
      expect(type.missing?('')).to be(false)
    end

    it 'rbs_type is nil' do
      expect(type.rbs_type).to be_nil
    end
  end

  describe '#inspect' do
    it 'names the class' do
      expect(type.inspect).to eq('#<FieldStruct::Types::Base>')
    end

    it 'uses AnonymousType for anonymous classes' do
      expect(Class.new(described_class).new.inspect).to eq('#<AnonymousType>')
    end

    it 'follows the alias namespace' do
      FieldStruct.instance_variable_set(:@inspect_namespace, 'FS')
      expect(type.inspect).to eq('#<FS::Types::Base>')
    ensure
      FieldStruct.instance_variable_set(:@inspect_namespace, nil)
    end

    it 'pretty prints the same text' do
      expect(PP.pp(type, +'').chomp).to eq(type.inspect)
    end
  end

  describe '.option' do
    it 'builds a frozen descriptor, accepting one class or many' do
      one = described_class.option(type: Integer)
      many = described_class.option(type: [Array, Range], required: true, presets: %i[a b])
      expect(one).to eq(type: [Integer], required: false, presets: [])
      expect(many).to eq(type: [Array, Range], required: true, presets: %i[a b])
      [one, one[:type], one[:presets], many].each { |v| expect(v).to be_frozen }
    end
  end

  describe '.option_schema' do
    let(:parent) do
      Class.new(described_class) do
        def self.own_option_schema
          { a: option(type: Integer), b: option(type: String) }
        end
      end
    end
    let(:child) do
      p = parent
      Class.new(p) do
        def self.own_option_schema
          { b: option(type: Symbol), c: option(type: Float) }
        end
      end
    end

    it 'is empty by default' do
      expect(described_class.own_option_schema).to eq({})
      expect(described_class.option_schema).to eq({})
    end

    it 'is frozen and memoized' do
      expect(parent.option_schema).to be_frozen
      expect(parent.option_schema).to equal(parent.option_schema)
    end

    it 'merges the superclass schema with own, own winning, inherited keys keeping position' do
      expect(child.option_schema.keys).to eq(%i[a b c])
      expect(child.option_schema[:b][:type]).to eq([Symbol])
      expect(parent.option_schema[:b][:type]).to eq([String])
    end
  end

  describe '.resolve_options' do
    it 'returns options unchanged by default' do
      options = { a: 1 }
      expect(described_class.resolve_options(options)).to equal(options)
    end
  end

  describe '.resolve_format' do
    it 'passes nil and Strings through' do
      expect(described_class.resolve_format(nil)).to be_nil
      expect(described_class.resolve_format('%Y')).to eq('%Y')
    end

    it 'refuses anything else naming the type' do
      expect { described_class.resolve_format(:x) }
        .to raise_error(ArgumentError, 'Base has no format presets; got :x')
    end
  end
end

RSpec.describe FieldStruct::Types::PresetResolver do
  let(:presets) { { a: 1, b: 2 } }

  it 'replaces a Symbol value by its preset, keeping key position' do
    result = described_class.call({ x: 0, k: :b, y: 9 }, :k, presets, label: 'thing')
    expect(result).to eq(x: 0, k: 2, y: 9)
    expect(result.keys).to eq(%i[x k y])
  end

  it 'does not mutate its input' do
    options = { k: :a }
    described_class.call(options, :k, presets, label: 'thing')
    expect(options).to eq(k: :a)
  end

  it 'passes absent keys and non-Symbol values through' do
    expect(described_class.call({ x: 1 }, :k, presets, label: 't')).to eq(x: 1)
    expect(described_class.call({ k: 'raw' }, :k, presets, label: 't')).to eq(k: 'raw')
  end

  it 'raises ArgumentError for an unknown preset' do
    expect { described_class.call({ k: :zz }, :k, presets, label: ':uuid format') }
      .to raise_error(ArgumentError, 'unknown :uuid format preset :zz. Available: [:a, :b]')
  end
end
