# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Boolean do
  subject(:type) { described_class.new }

  it 'FS-B164: ruby_type is [TrueClass, FalseClass]' do
    expect(type.ruby_type).to eq([TrueClass, FalseClass])
  end

  it 'declares values: Hash or Symbol' do
    expect(described_class.option_schema.keys).to eq(%i[values])
    expect(described_class.option_schema[:values][:type]).to eq([Hash, Symbol])
  end

  it 'FS-B163: exposes default_truthy, default_falsy and presets' do
    expect(described_class.default_truthy).to eq(%w[true 1])
    expect(described_class.default_falsy).to eq(%w[false 0])
    expect(described_class.presets.keys).to eq(%i[english_yes_no english numeric])
    expect(described_class.presets[:numeric]).to eq(truthy: ['1'], falsy: ['0'])
    expect(described_class.presets[:english]).to eq(described_class.presets[:english_yes_no])
    expect(described_class.presets[:english_yes_no]).to eq(truthy: %w[true yes y on 1], falsy: %w[false no n off 0])
  end

  it 'FS-B33: missing only for nil, false is present' do
    expect(type.missing?(nil)).to be(true)
    expect(type.missing?(false)).to be(false)
  end

  describe 'FS-B68 coercion' do
    it 'passes true, false and nil' do
      expect(type.coerce(true)).to be(true)
      expect(type.coerce(false)).to be(false)
      expect(type.coerce(nil)).to be_nil
    end

    it 'reads 1/0 and 1.0/0.0' do
      expect(type.coerce(1)).to be(true)
      expect(type.coerce(0)).to be(false)
      expect(type.coerce(1.0)).to be(true)
      expect(type.coerce(0.0)).to be(false)
    end

    it 'reads the default strings case-insensitively' do
      %w[true TRUE True 1].each { |v| expect(type.coerce(v)).to be(true) }
      %w[false FALSE False 0].each { |v| expect(type.coerce(v)).to be(false) }
    end

    it 'does not trim and does not know yes/no by default' do
      [' true', 'true ', 'yes', ''].each do |v|
        expect { type.coerce(v) }.to raise_error(ArgumentError, /got a String that is not one\z/)
      end
    end

    it 'refuses with a class-only message listing the active vocabulary' do
      expect { type.coerce('maybe') }.to raise_error(
        ArgumentError,
        'Boolean fields expect true, false, 1, 0 or one of the strings "true", "1", "false", "0", got a String that is not one'
      )
      expect { type.coerce(:yes) }.to raise_error(ArgumentError, /, got Symbol\z/)
      expect { type.coerce(2) }.to raise_error(ArgumentError, /, got Integer\z/)
    end
  end

  describe 'FS-B69 values:' do
    it 'uses a Hash vocabulary for strings only, wrapping scalars' do
      values = { truthy: %w[Yes], falsy: 'no' }
      expect(type.coerce('yes', values: values)).to be(true)
      expect(type.coerce('NO', values: values)).to be(false)
      expect(type.coerce(true, values: values)).to be(true)
      expect(type.coerce(1, values: values)).to be(true)
      expect(type.coerce(0, values: values)).to be(false)
      expect { type.coerce('true', values: values) }
        .to raise_error(ArgumentError, /one of the strings "Yes", "no", got a String/i)
    end

    it 'resolves presets at declaration' do
      resolved = described_class.resolve_options(values: :numeric)
      expect(resolved).to eq(values: { truthy: ['1'], falsy: ['0'] })
      expect(described_class.resolve_options(values: :english_yes_no)[:values][:truthy]).to include('yes')
      expect(described_class.resolve_options({})).to eq({})
    end

    it 'raises for an unknown preset' do
      expect { described_class.resolve_options(values: :nope) }.to raise_error(
        ArgumentError,
        'unknown :boolean values preset :nope. Available: [:english_yes_no, :english, :numeric]'
      )
    end

    it 'reads default_truthy / default_falsy of a subclass inside coerce' do
      subclass = Class.new(described_class) do
        def self.default_truthy = %w[si]
        def self.default_falsy = %w[no]
      end
      expect(subclass.new.coerce('SI')).to be(true)
      expect(subclass.new.coerce('no')).to be(false)
      expect { subclass.new.coerce('true') }.to raise_error(ArgumentError)
    end
  end
end
