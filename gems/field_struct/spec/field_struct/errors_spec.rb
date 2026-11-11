# frozen_string_literal: true

RSpec.describe FieldStruct::Errors do
  subject(:errors) { described_class.new }

  it 'starts empty' do
    expect(errors).to be_empty
    expect(errors.to_h).to eq({})
  end

  describe '#[]' do
    it 'returns [] for a field with no messages, without storing it' do
      expect(errors[:name]).to eq([])
      errors[:name] << 'x'
      expect(errors).to be_empty
    end

    it 'accepts String or Symbol keys' do
      errors.add(:name, 'is required')
      expect(errors['name']).to eq(['is required'])
    end
  end

  describe '#add' do
    it 'appends messages and creates the entry' do
      errors.add(:name, 'is required')
      errors.add(:name, 'is invalid')
      expect(errors[:name]).to eq(['is required', 'is invalid'])
      expect(errors).not_to be_empty
    end
  end

  describe '#clear' do
    it 'removes only that field and returns nil' do
      errors.add(:a, 'x')
      errors.add(:b, 'y')
      expect(errors.clear(:a)).to be_nil
      expect(errors.to_h).to eq(b: ['y'])
    end
  end

  describe '#empty?' do
    it 'counts an entry holding an empty array as none' do
      errors[:a]
      errors.add(:a, 'x')
      errors[:a].clear
      expect(errors).to be_empty
    end
  end

  describe '#to_h / #messages' do
    it 'only lists fields with messages, in first-add order, as a new Hash' do
      errors.add(:b, 'x')
      errors.add(:a, 'y')
      errors.add(:b, 'z')
      expect(errors.to_h).to eq(b: %w[x z], a: ['y'])
      expect(errors.to_h.keys).to eq(%i[b a])
      expect(errors.messages).to eq(errors.to_h)
      expect(errors.to_h).not_to equal(errors.to_h)
    end
  end

  describe '#full_messages' do
    it 'humanizes the field name and leaves :base bare' do
      errors.add(:first_name, 'is required')
      errors.add(:base, 'is odd')
      expect(errors.full_messages).to eq(['First name is required', 'is odd'])
    end

    it 'FS-B164: gives "Id is required"' do
      errors.add(:id, 'is required')
      expect(errors.full_messages).to eq(['Id is required'])
    end
  end

  describe '#inspect' do
    it 'shows empty' do
      expect(errors.inspect).to eq('#<FieldStruct::Errors empty>')
    end

    it 'shows space separated pairs' do
      errors.add(:name, 'is required')
      errors.add(:height, 'is invalid')
      expect(errors.inspect).to eq('#<FieldStruct::Errors name=["is required"] height=["is invalid"]>')
    end
  end

  describe 'copying' do
    it 'deep-copies the message arrays on dup and clone' do
      errors.add(:a, 'x')
      [errors.dup, errors.clone].each do |copy|
        copy.add(:a, 'y')
        expect(errors[:a]).to eq(['x'])
      end
    end
  end
end
