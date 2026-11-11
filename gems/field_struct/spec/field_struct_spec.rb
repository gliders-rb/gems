# frozen_string_literal: true

RSpec.describe FieldStruct do
  it 'has a version' do
    expect(FieldStruct::VERSION).to eq('1.0.0.pre1')
  end

  it 'exposes the FILTERED placeholder' do
    expect(FieldStruct::FILTERED).to eq('[FILTERED]')
  end

  describe '.root' do
    it 'is the Pathname of the directory holding lib/' do
      expect(FieldStruct.root).to be_a(Pathname)
      expect(FieldStruct.root.join('lib', 'field_struct.rb')).to exist
      expect(FieldStruct.root).to equal(FieldStruct.root)
    end
  end

  describe '.types' do
    it 'FS-B124: is memoized and has no parent' do
      expect(FieldStruct.types).to equal(FieldStruct.types)
      expect(FieldStruct.types.parent).to be_nil
    end
  end

  describe '.new_registry' do
    it 'FS-B125: defaults the parent to FieldStruct.types' do
      expect(FieldStruct.new_registry.parent).to equal(FieldStruct.types)
    end

    it 'FS-B125: accepts an explicit parent' do
      parent = FieldStruct::Registry.new
      expect(FieldStruct.new_registry(parent).parent).to equal(parent)
    end

    it 'FS-B125: nil gives an unparented registry' do
      expect(FieldStruct.new_registry(nil).parent).to be_nil
    end

    it 'FS-B125: evaluates the block with the registry as self' do
      klass = Class.new(FieldStruct::Types::Base)
      registry = FieldStruct.new_registry(nil) { register :thing, klass }
      expect(registry.lookup(:thing)).to equal(klass)
    end

    it 'FS-B125: without a block still returns the registry' do
      expect(FieldStruct.new_registry).to be_a(FieldStruct::Registry)
    end
  end

  describe '.use_alias!' do
    after do
      Object.send(:remove_const, :FS) if Object.const_defined?(:FS)
      FieldStruct.instance_variable_set(:@inspect_namespace, nil)
    end

    it 'defaults the namespace to FieldStruct' do
      expect(FieldStruct.inspect_namespace).to eq('FieldStruct')
    end

    it 'FS-B118: defines the constant and switches the inspect prefix' do
      expect(FieldStruct.use_alias!).to equal(FieldStruct)
      expect(FS).to equal(FieldStruct)
      expect(FieldStruct.inspect_namespace).to eq('FS')
      expect(FieldStruct::Errors.new.inspect).to eq('#<FS::Errors empty>')
    end

    it 'FS-B118: is idempotent for the same constant' do
      FieldStruct.use_alias!
      expect { FieldStruct.use_alias! }.not_to raise_error
    end

    it 'FS-B118: raises NameError when the constant is something else' do
      Object.const_set(:FS, Module.new)
      expect { FieldStruct.use_alias! }
        .to raise_error(NameError, /\A::FS is already defined \(.*\); not aliasing FieldStruct\z/)
    end
  end
end
