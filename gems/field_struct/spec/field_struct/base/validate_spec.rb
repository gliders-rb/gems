# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'cross-field validation' do
  let(:klass) do
    Class.new(described_class) do
      optional :low, :integer
      optional :high, :integer
      validate :ordered
      validate { |record| record.errors.add(:base, 'both missing') if record.low.nil? && record.high.nil? }

      def ordered
        errors.add(:base, 'low above high') if low && high && low > high
      end
    end
  end

  it 'FS-B47: runs method names and blocks in declaration order; validate returns the class' do
    expect(klass.validate { nil }).to equal(klass)
    expect(klass.new(low: 5, high: 1).errors[:base]).to eq(['low above high'])
    expect(klass.new.errors[:base]).to eq(['both missing'])
  end

  it 'FS-B47: registers each method name as its own validator' do
    two = Class.new(described_class) do
      validate :a, :b

      def a = errors.add(:base, 'a')
      def b = errors.add(:base, 'b')
    end
    expect(two.validators.size).to eq(2)
    expect(two.new.errors[:base]).to eq(%w[a b])
  end

  it 'FS-B48: shows base errors on a fresh instance and re-runs at valid?' do
    instance = klass.new(low: 1, high: 2)
    expect(instance).to be_valid
    instance.low = 9
    expect(instance.valid?).to be(false)
    instance.low = 1
    expect(instance.valid?).to be(true)
  end

  it 'FS-B48: classes with none have an empty validators list' do
    plain = Class.new(described_class)
    expect(plain.validators).to be_empty
    expect(plain.new).to be_valid
  end

  it 'FS-B49: clears :base before a run but leaves field errors alone' do
    instance = klass.new(low: 5, high: 1)
    2.times { instance.valid? }
    expect(instance.errors[:base]).to eq(['low above high'])
    broken = klass.new(low: 'x', high: nil)
    broken.valid?
    expect(broken.errors[:low].size).to eq(1)
  end

  it 'FS-B50: inherits a copy of the list; the parent never changes' do
    child = Class.new(klass) { validate { |r| r.errors.add(:base, 'child') } }
    expect(klass.validators.size).to eq(2)
    expect(child.validators.size).to eq(3)
    expect(child.new(low: 5, high: 1).errors[:base]).to eq(['low above high', 'child'])
    expect(klass.new(low: 5, high: 1).errors[:base]).to eq(['low above high'])
  end

  it 'FS-B51: lets an exception in a validator propagate' do
    boom = Class.new(described_class) { validate { raise IOError, 'boom' } }
    expect { boom.new }.to raise_error(IOError, 'boom')
  end

  it 'works on frozen instances' do
    frozen = Class.new(klass) { frozen! }.new(low: 5, high: 1)
    expect(frozen.valid?).to be(false)
  end
end
