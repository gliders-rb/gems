# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'instance surface' do
  let(:klass) do
    Class.new(described_class) do
      required :name, :string
      optional :height, :integer
    end
  end

  describe '#attributes / #to_h' do
    it 'returns canonical names in declaration order as a fresh Hash' do
      instance = klass.new(height: '3', name: 'a')
      expect(instance.attributes).to eq(name: 'a', height: 3)
      expect(instance.attributes.keys).to eq(%i[name height])
      expect(instance.attributes).not_to equal(instance.attributes)
      expect(instance.to_h).to eq(instance.attributes)
    end
  end

  describe 'FS-B112 equality' do
    it 'is structural over class and attributes, ignoring errors' do
      a = klass.new(name: 'a', height: 1)
      b = klass.new(name: 'a', height: 1)
      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
      expect(klass.new(name: 'a', height: 'bad')).not_to eq(a)
      expect(klass.new).to eq(klass.new)
    end

    it 'treats a subclass instance as different, in both directions, and other objects too' do
      sub = Class.new(klass)
      expect(klass.new(name: 'a')).not_to eq(sub.new(name: 'a'))
      expect(sub.new(name: 'a')).not_to eq(klass.new(name: 'a'))
      expect(klass.new(name: 'a')).not_to eq({ name: 'a', height: nil })
    end

    it 'collapses equal instances in a Set and works as Hash keys' do
      expect(Set.new([klass.new(name: 'a'), klass.new(name: 'a')]).size).to eq(1)
      expect({ klass.new(name: 'a') => 1 }[klass.new(name: 'a')]).to eq(1)
    end
  end

  describe 'FS-B113 dup and clone' do
    it 'gives the copy its own Errors holding copies of the messages' do
      original = klass.new(name: 'a')
      copy = original.dup
      copy.name = ''
      expect(copy).to be_invalid
      expect(original).to be_valid
      broken = klass.new
      copy2 = broken.clone
      expect(copy2.errors.to_h).to eq(broken.errors.to_h)
      copy2.name = 'x'
      expect(broken).to be_invalid
    end

    it 'copies shallowly' do
      holder = Class.new(described_class) { field :tags, :value }
      tags = []
      expect(holder.new(tags: tags).dup.tags).to equal(tags)
    end

    it 'dup of a frozen instance is unfrozen; clone stays frozen unless freeze: false' do
      frozen = klass.new(name: 'a').freeze
      expect(frozen.dup).not_to be_frozen
      expect(frozen.clone).to be_frozen
      expect(frozen.clone(freeze: false)).not_to be_frozen
      expect(frozen.errors).not_to be_frozen
    end
  end

  describe 'FS-B115 inspect' do
    it 'renders name: value pairs in declaration order' do
      stub_const('Warden', klass)
      expect(klass.new(name: 'x', height: 3).inspect).to eq('#<Warden name: "x", height: 3>')
    end

    it 'appends the errors with a single space and no comma' do
      stub_const('Warden', klass)
      expect(klass.new(name: 'x', height: 'abc').inspect).to eq(
        '#<Warden name: "x", height: "abc" errors: {height: ["could not be coerced: Integer fields expect a base-10 integer, ' \
        'got a String that is not one"]}>'
      )
    end

    it 'joins several errors with ", "' do
      stub_const('Warden', klass)
      expect(klass.new(height: 'abc').inspect).to match(/errors: \{name: \["is required"\], height: \["could not/)
    end

    it 'names anonymous classes AnonymousFieldStruct and prints #<Name > for no fields' do
      expect(klass.new(name: 'x').inspect).to start_with('#<AnonymousFieldStruct name: "x"')
      stub_const('Empty', Class.new(described_class))
      expect(Empty.new.inspect).to eq('#<Empty >')
    end

    it 'shows nil for unset values and masks non-nil sensitive values' do
      secret = Class.new(described_class) do
        field :token, :string, sensitive: true
        field :other, :string
      end
      expect(secret.new(token: 'abc').inspect).to eq('#<AnonymousFieldStruct token: [FILTERED], other: nil>')
      expect(secret.new.inspect).to eq('#<AnonymousFieldStruct token: nil, other: nil>')
    end

    it 'never re-runs validation' do
      instance = klass.new(name: 'a')
      instance.instance_variable_set(:@name, nil)
      expect(instance.inspect).to eq('#<AnonymousFieldStruct name: nil, height: nil>')
    end
  end

  describe 'FS-B117 model_name and to_model' do
    it 'is memoized per class and shared with instances' do
      stub_const('Nursery::LineItem', Class.new(described_class))
      expect(Nursery::LineItem.model_name).to equal(Nursery::LineItem.model_name)
      expect(Nursery::LineItem.model_name).to be_a(FieldStruct::ModelName)
      expect(Nursery::LineItem.new.model_name).to equal(Nursery::LineItem.model_name)
      expect(Nursery::LineItem.model_name.element).to eq('line_item')
    end

    it 'to_model returns self' do
      instance = klass.new
      expect(instance.to_model).to equal(instance)
    end

    it 'does not define persistence methods' do
      %i[to_key to_param to_partial_path persisted? new_record?].each do |name|
        # ActiveSupport (the AS lane) defines some of these on Object; only FieldStruct's own definitions count.
        owner = klass.new.method(name).owner if klass.new.respond_to?(name)
        expect(owner).to be_nil.or(satisfy { |mod| !mod.name.to_s.start_with?('FieldStruct') && mod != klass })
      end
    end
  end

  describe 'FS-B155 / FS-B156 through a declared class' do
    it 'exposes Field readers' do
      with = Class.new(described_class) { optional :a, :integer, default: false, desc: 'A' }
      field = with.metadata[:a]
      expect(field.default).to be(false)
      expect(field.desc).to eq('A')
      expect(field).to be_frozen
    end
  end
end
