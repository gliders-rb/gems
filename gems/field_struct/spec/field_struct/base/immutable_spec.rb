# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'immutable! and frozen!' do
  def build(&block)
    Class.new(described_class) do
      required :name, :string
      optional :height, :integer
      class_eval(&block) if block
    end
  end

  describe 'FS-B29 immutable!' do
    let(:klass) { build(&:immutable!) }

    it 'allows setters during new and refuses them afterwards, before coercing' do
      stub_const('Frozen', klass)
      instance = klass.new(name: 'a')
      expect(instance.name).to eq('a')
      expect { instance.name = 'b' }.to raise_error(FieldStruct::ImmutableError, 'Frozen is immutable; cannot reassign name')
      expect { instance.assign_attributes(height: 1) }.to raise_error(FieldStruct::ImmutableError)
      expect(instance.name).to eq('a')
    end

    it 'still allows reads, dup, with and as plain values' do
      instance = klass.new(name: 'a')
      expect(instance.with(name: 'b').name).to eq('b')
      expect(instance.dup.name).to eq('a')
    end

    it 'returns true, is inherited, and a child of a mutable parent can opt in' do
      parent = build
      expect(parent.immutable?).to be(false)
      child = Class.new(parent) { immutable! }
      expect(child.immutable!).to be(true)
      expect(child.immutable?).to be(true)
      expect(parent.immutable?).to be(false)
      expect(Class.new(child).immutable?).to be(true)
      expect(described_class.immutable?).to be(false)
    end

    it 'names an anonymous class by its inspect in the message' do
      instance = klass.new(name: 'a')
      expect { instance.name = 'b' }.to raise_error(FieldStruct::ImmutableError, /#<Class:0x\h+> is immutable/)
    end
  end

  describe 'FS-B30 frozen!' do
    let(:klass) { build(&:frozen!) }

    it 'freezes the instance at the end of new and setters then raise FrozenError' do
      instance = klass.new(name: 'a')
      expect(instance).to be_frozen
      expect { instance.name = 'b' }.to raise_error(FrozenError)
    end

    it 'keeps reads, valid? and errors usable' do
      instance = klass.new
      expect(instance.valid?).to be(false)
      expect(instance.errors[:name]).to eq(['is required'])
      expect(instance.attributes).to eq(name: nil, height: nil)
      instance.errors.add(:name, 'extra')
    end

    it 'is one-way and inherited; frozen_on_construct? reads through the chain' do
      expect(described_class.frozen_on_construct?).to be(false)
      expect(klass.frozen_on_construct?).to be(true)
      expect(Class.new(klass).frozen_on_construct?).to be(true)
      expect(klass.frozen!).to be(true)
    end

    it 'raises ImmutableError first when both are set' do
      both = build do
        immutable!
        frozen!
      end
      expect { both.new(name: 'a').name = 'b' }.to raise_error(FieldStruct::ImmutableError)
    end
  end

  describe 'FS-B113 dup / clone' do
    it 'dup of a frozen instance is unfrozen, clone stays frozen, clone(freeze: false) does not' do
      instance = build(&:frozen!).new(name: 'a')
      expect(instance.dup).not_to be_frozen
      expect(instance.clone).to be_frozen
      expect(instance.clone(freeze: false)).not_to be_frozen
    end

    it 'gives the copy its own Errors' do
      original = build.new(name: 'a')
      copy = original.dup
      copy.name = ''
      expect(copy).to be_invalid
      expect(original).to be_valid
    end
  end
end
