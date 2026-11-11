# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'the setter pipeline' do
  let(:klass) do
    Class.new(described_class) do
      required :name, :string
      optional :height, :integer
      optional :active, :boolean
      optional :score, :float
    end
  end

  subject(:instance) { klass.new(name: 'Fern') }

  it 'FS-B28: is permissive, coercing on every assignment' do
    instance.height = '30'
    expect(instance.height).to eq(30)
    expect(instance).to be_valid
  end

  it 'FS-B24: the writer expression yields the assigned value; fields keep the coerced one' do
    instance.score = '2.5'
    expect(instance.score).to eq(2.5)
  end

  describe 'FS-B32 / FS-B33 presence' do
    it 'rewrites that field\'s errors on every assignment and leaves other fields alone (FS-I1)' do
      broken = klass.new
      expect(broken.errors.to_h).to eq(name: ['is required'])
      broken.height = nil
      expect(broken.errors.to_h).to eq(name: ['is required'])
      broken.name = '   '
      expect(broken.errors.to_h).to eq(name: ['is required'])
      broken.name = 'Fern'
      expect(broken.errors).to be_empty
      broken.name = ''
      expect(broken.errors.to_h).to eq(name: ['is required'])
    end

    it 'does not require optional fields' do
      instance.height = nil
      expect(instance).to be_valid
    end

    it 'treats 0, 0.0 and false as present' do
      strict_class = Class.new(described_class) do
        required :i, :integer
        required :f, :float
        required :b, :boolean
      end
      expect(strict_class.new(i: 0, f: 0.0, b: false)).to be_valid
    end
  end

  describe 'FS-B43 / FS-B28 default coercion failure (keep_raw)' do
    it 'stores the raw input and records a single could-not-be-coerced error' do
      instance.height = 'abc'
      expect(instance.height).to eq('abc')
      expect(instance.errors.to_h).to eq(
        height: ['could not be coerced: Integer fields expect a base-10 integer, got a String that is not one']
      )
      expect(instance).to be_invalid
    end

    it 'FS-B42: records only the coercion error for a required field' do
      strict_class = Class.new(described_class) { required :n, :integer }
      expect(strict_class.new(n: 'x').errors[:n].size).to eq(1)
      expect(strict_class.new(n: 'x').errors[:n].first).to start_with('could not be coerced')
    end

    it 'clears the coercion error on a later good assignment' do
      instance.height = 'abc'
      instance.height = '5'
      expect(instance).to be_valid
      expect(instance.height).to eq(5)
    end

    it 'does not echo the input in the message' do
      instance.height = 'S3CR3T'
      expect(instance.errors.to_h.to_s).not_to include('S3CR3T')
    end
  end

  describe 'FS-B41 valid? / invalid?' do
    it 'reflects errors' do
      expect(instance).to be_valid
      expect(instance.invalid?).to be(false)
      instance.name = nil
      expect(instance.valid?).to be(false)
      expect(instance.invalid?).to be(true)
    end
  end

  describe 'FS-B15 field options reach coerce' do
    it 'passes all options as keywords, including pass-through ones' do
      rounded = Class.new(described_class) { field :f, :float, round: 1, avro_doc: 'x' }
      expect(rounded.new(f: '1.25').f).to eq(1.3)
    end
  end
end
