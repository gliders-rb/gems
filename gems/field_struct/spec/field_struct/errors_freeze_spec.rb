# frozen_string_literal: true

RSpec.describe 'Frozen errors (FS-B40b)' do
  let(:tideline) do
    Class.new(FieldStruct::Base) do
      required :station, :string
      optional :low_m, :float
      optional :high_m, :float
      validate { |mark| mark.errors.add(:base, 'low above high') if mark.low_m.to_f > mark.high_m.to_f }
    end
  end

  it 'freezes the messages: add and clear raise, reads still work' do
    mark = tideline.new(low_m: 2.0, high_m: 1.0)
    mark.errors.freeze
    expect { mark.errors.add(:station, 'x') }.to raise_error(FrozenError)
    expect { mark.errors.clear(:station) }.to raise_error(FrozenError)
    expect { mark.errors[:station] << 'x' }.to raise_error(FrozenError)
    expect(mark.errors.to_h).to eq(station: ['is required'], base: ['low above high'])
    expect([mark.errors.paths.keys, mark.errors.full_messages.size]).to eq([%w[station base], 2])
  end

  it 'lets valid? read frozen errors without re-running the validators' do
    mark = tideline.new(station: 'Pier 4', low_m: 2.0, high_m: 1.0)
    mark.errors.freeze
    expect([mark.valid?, mark.invalid?]).to eq([false, true])
  end

  it 'gives a dup and a with their own unfrozen errors' do
    mark = tideline.new(low_m: 2.0, high_m: 1.0)
    mark.errors.freeze
    copy = mark.dup
    copy.errors.add(:station, 'checked')
    expect([copy.errors.frozen?, mark.errors[:station]]).to eq([false, ['is required']])
    expect(mark.with(station: 'Pier 4', high_m: 3.0)).to be_valid
  end

  it 'leaves frozen! structs re-running their validators' do
    fixed = Class.new(tideline) { frozen! }
    mark = fixed.new(station: 'Pier 4', low_m: 1.0, high_m: 2.0)
    expect([mark.frozen?, mark.errors.frozen?, mark.valid?]).to eq([true, false, true])
  end
end
