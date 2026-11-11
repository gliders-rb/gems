# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'value restrictions' do
  def build(type, **options)
    Class.new(described_class) { field :x, type, **options }
  end

  describe 'FS-B35 / FS-B36 / FS-B37' do
    it 'flags a Regexp format mismatch as "is invalid" on the coerced value' do
      klass = build(:string, format: /\A\d+\z/)
      expect(klass.new(x: 12).errors).to be_empty
      expect(klass.new(x: 'ab').errors.to_h).to eq(x: ['is invalid'])
    end

    it 'checks enum: with include? after coercion' do
      klass = build(:symbol, enum: %i[before after])
      expect(klass.new(x: 'before').errors).to be_empty
      expect(klass.new(x: 'during').errors[:x]).to eq(['is invalid'])
    end

    it 'checks in: with an Array (include?) or Range (cover?)' do
      ints = build(:integer, in: 1..10)
      expect(ints.new(x: '10')).to be_valid
      expect(ints.new(x: 11).errors[:x]).to eq(['is invalid'])
      expect(build(:integer, in: (10..)).new(x: 1_000_000)).to be_valid
      expect(build(:float, in: 1.0..10.0).new(x: '2.5')).to be_valid
      expect(build(:integer, in: [1, 3]).new(x: 2).errors[:x]).to eq(['is invalid'])
    end

    it 'never flags nil: an optional nil is valid, a required nil is "is required"' do
      expect(build(:integer, in: 1..2).new(x: nil)).to be_valid
      req = Class.new(described_class) { required :x, :integer, in: 1..2 }
      expect(req.new(x: nil).errors[:x]).to eq(['is required'])
    end

    it 'adds a single "is invalid" however many checks fail' do
      klass = build(:string, format: /\Aa\z/, enum: %w[b])
      expect(klass.new(x: 'c').errors[:x]).to eq(['is invalid'])
    end

    it 'checks "is required" before "is invalid" for blank strings' do
      klass = Class.new(described_class) { required :x, :string, format: /\Aa\z/ }
      expect(klass.new(x: ' ').errors[:x]).to eq(['is required'])
    end

    it 'FS-B38: ignores a Symbol format (not a validation regexp)' do
      expect(build(:string, format: :preset).new(x: 'zz')).to be_valid
    end

    it 'rewrites the error when a bad value is fixed' do
      instance = build(:integer, in: 1..2).new(x: 5)
      expect(instance).to be_invalid
      instance.x = 1
      expect(instance).to be_valid
    end
  end

  describe 'FS-B56 uuid / url / email' do
    it 'validates with the prefilled default format' do
      klass = Class.new(described_class) do
        field :id, :uuid
        field :border, :url
        field :mail, :email
      end
      ok = klass.new(id: '123e4567-e89b-12d3-a456-426614174000', border: 'https://x.test/a', mail: 'a@b.co')
      expect(ok).to be_valid
      bad = klass.new(id: 'not-a-uuid', border: 'ftp://x', mail: 'nope')
      expect(bad.errors.to_h).to eq(id: ['is invalid'], border: ['is invalid'], mail: ['is invalid'])
      expect(bad.id).to eq('not-a-uuid')
    end

    it 'honours presets and explicit Regexps' do
      expect(build(:uuid, format: :v4).new(x: '123e4567-e89b-72d3-a456-426614174000')).to be_invalid
      expect(build(:url, format: :https_only).new(x: 'http://x.test')).to be_invalid
      expect(build(:url, format: :any_scheme).new(x: 'ftp://x.test/a')).to be_valid
      expect(build(:email, format: :permissive).new(x: 'a@b')).to be_valid
      expect(build(:email, format: :strict).new(x: 'a@b')).to be_invalid
      expect(build(:email, format: /\Az\z/).new(x: 'z')).to be_valid
    end

    it 'treats blank as required' do
      klass = Class.new(described_class) { required :x, :uuid }
      expect(klass.new(x: '  ').errors[:x]).to eq(['is required'])
    end
  end
end
