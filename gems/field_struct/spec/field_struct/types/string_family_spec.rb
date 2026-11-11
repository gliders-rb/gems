# frozen_string_literal: true

RSpec.describe 'string-family types' do
  describe FieldStruct::Types::UUID do
    subject(:type) { described_class.new }

    it 'FS-B56: coerces like :string' do
      expect(type.coerce(12)).to eq('12')
      expect(type.coerce(nil)).to be_nil
      expect(type.ruby_type).to eq(String)
      expect(type.missing?('  ')).to be(true)
    end

    it 'FS-B53: honours strict: true' do
      expect { type.coerce(1.5, strict: true) }.to raise_error(TypeError, /strict: true expect/)
    end

    it 'has the preset table, default and schema' do
      expect(described_class.presets.keys).to eq(%i[any_version v4 v7])
      expect(described_class.default_format).to equal(described_class.presets[:any_version])
      expect(described_class.option_schema.keys).to eq(%i[format enum strict])
      expect(described_class.option_schema[:format][:presets]).to eq(%i[any_version v4 v7])
      expect(described_class.presets[:v7]).to match('018f0000-0000-7000-8000-000000000000')
      expect(described_class.presets[:v4]).not_to match('018f0000-0000-7000-8000-000000000000')
    end
  end

  describe FieldStruct::Types::URL do
    it 'has presets http, https_only and any_scheme; http is the default' do
      expect(described_class.presets.keys).to eq(%i[http https_only any_scheme])
      expect(described_class.default_format).to equal(described_class.presets[:http])
      expect(described_class.presets[:http]).to match('HTTP://example.test/a')
      expect(described_class.presets[:http]).not_to match('http:// bad')
      expect(described_class.presets[:any_scheme]).to match('git+ssh://host/x')
    end
  end

  describe FieldStruct::Types::Email do
    it 'has presets permissive, default and strict; default is the default' do
      expect(described_class.presets.keys).to eq(%i[permissive default strict])
      expect(described_class.default_format).to equal(described_class.presets[:default])
      expect(described_class.presets[:permissive]).to match('a@b')
      expect(described_class.presets[:default]).not_to match('a@b')
      expect(described_class.presets[:strict]).to match('a.b+c@example.co.uk')
      expect(described_class.presets[:strict]).not_to match('a@-b.com')
    end

    it 'is wrapped by resolve_options' do
      resolved = described_class.resolve_options({ format: :strict, enum: nil })
      expect(resolved[:format]).to be_a(Regexp)
    end
  end

  describe FieldStruct::Types::Binary do
    subject(:type) { described_class.new }

    it 'FS-B55: returns an ASCII-8BIT copy with the same bytes and does not mutate the input' do
      input = +'é'
      result = type.coerce(input)
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
      expect(result.bytesize).to eq(2)
      expect(input.encoding).to eq(Encoding::UTF_8)
      expect(type.coerce(nil)).to be_nil
    end

    it 'FS-B55 / FS-B161: whitespace is present, empty is missing' do
      expect(type.missing?(' ')).to be(false)
      expect(type.missing?('')).to be(true)
      expect(type.missing?(nil)).to be(true)
    end

    it 'declares the string schema, no default_format, ruby_type String' do
      expect(described_class.option_schema.keys).to eq(%i[format enum strict])
      expect(described_class).not_to respond_to(:default_format)
      expect(type.ruby_type).to eq(String)
      expect { type.coerce(1.5, strict: true) }.to raise_error(TypeError)
    end
  end

  it 'FS-B124: registers them under their names, in table order' do
    names = FieldStruct.types.type_classes.map(&:short_name)
    expect(names).to eq(%w[String ImmutableString Integer Float BigDecimal Boolean Date Time DateTime Value Array Symbol UUID URL Email
                           Union Binary])
  end

  it 'FS-B163: String, Integer and Symbol define no default_format' do
    [FieldStruct::Types::String, FieldStruct::Types::Integer, FieldStruct::Types::Symbol].each do |type|
      expect(type).not_to respond_to(:default_format)
    end
  end
end
