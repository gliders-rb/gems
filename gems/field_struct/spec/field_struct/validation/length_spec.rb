# frozen_string_literal: true

RSpec.describe 'length: on the string family (FS-B37a)' do
  let(:kite) do
    Class.new(FieldStruct::Base) do
      required :callsign, :string, length: 3..12
      optional :motto, :string, length: ..20
      optional :tail, :string, length: 2..
    end
  end

  it 'accepts a value inside the bounds, ends included' do
    expect(kite.new(callsign: 'Osp', motto: 'x' * 20, tail: 'ab')).to be_valid
  end

  it 'names the minimum when the value is too short' do
    expect(kite.new(callsign: 'Ka').errors.to_h).to eq(callsign: ['is too short (minimum is 3)'])
  end

  it 'names the maximum when the value is too long' do
    expect(kite.new(callsign: 'Peregrine-Nine').errors.to_h).to eq(callsign: ['is too long (maximum is 12)'])
  end

  it 'reads an exclusive end as a maximum one less' do
    gull = Class.new(FieldStruct::Base) { required :cry, :string, length: 1...4 }
    expect([gull.new(cry: 'kee').valid?, gull.new(cry: 'keee').errors[:cry]]).to eq([true, ['is too long (maximum is 3)']])
  end

  it 'never echoes the input or its length' do
    message = kite.new(callsign: 'Q').errors[:callsign].first
    expect(message).not_to match(/\bQ\b|\b1\b/)
  end

  it 'counts characters, not bytes' do
    expect(kite.new(callsign: 'ñandú')).to be_valid
  end

  it 'counts bytes on :binary' do
    blob = Class.new(FieldStruct::Base) { required :chunk, :binary, length: ..4 }
    expect(blob.new(chunk: 'ñañ').errors[:chunk]).to eq(['is too long (maximum is 4)'])
  end

  it 'lets a missing value skip it: blank optional passes, blank required is "is required"' do
    expect(kite.new(callsign: 'Osp', tail: '').valid?).to be(true)
    expect(kite.new(callsign: '  ').errors.to_h).to eq(callsign: ['is required'])
  end

  it 'gives one message: length wins over format' do
    coded = Class.new(FieldStruct::Base) { required :code, :string, length: 3..3, format: /\A[A-Z]+\z/ }
    expect([coded.new(code: 'ab').errors[:code], coded.new(code: 'abc').errors[:code]])
      .to eq([['is too short (minimum is 3)'], ['is invalid']])
  end

  it 'works on :uuid, :url, :email and :immutable_string' do
    kinds = Class.new(FieldStruct::Base) do
      optional :site, :url, length: ..30
      optional :mail, :email, length: ..10
      optional :tag, :immutable_string, length: 2..
    end
    errors = kinds.new(site: "https://#{'w' * 30}.example", mail: 'heron@marsh.example', tag: 'x').errors.to_h
    expect(errors).to eq(site: ['is too long (maximum is 30)'], mail: ['is too long (maximum is 10)'],
                         tag: ['is too short (minimum is 2)'])
  end

  it 'makes a broken element an element failure' do
    flock = Class.new(FieldStruct::Base) { optional :names, :array, of: :string, element: { length: ..5 } }
    expect(flock.new(names: %w[wren starling]).errors[:names]).to eq([FieldStruct::Types::Array.invalid_elements_message([1])])
  end

  describe 'at declaration' do
    it 'refuses a value that is not a Range with the generic shape message' do
      expect { Class.new(FieldStruct::Base) { optional :cry, :string, length: 3 } }
        .to raise_error(ArgumentError, 'length: on String expects Range, got Integer (3)')
    end

    it 'refuses ends that are not whole numbers from 0' do
      [1.5..4, -1..4, 'a'..'c'].each do |bad|
        expect { Class.new(FieldStruct::Base) { optional :cry, :string, length: bad } }
          .to raise_error(ArgumentError, "length: on String takes a Range of whole numbers from 0, like 3..40 or ..40, got #{bad.inspect}")
      end
    end

    it 'refuses an empty Range and one open at both ends' do
      expect { Class.new(FieldStruct::Base) { optional :cry, :string, length: 5..2 } }
        .to raise_error(ArgumentError, /takes a Range of whole numbers from 0.*got 5\.\.2\z/)
      expect { Class.new(FieldStruct::Base) { optional :cry, :string, length: nil..nil } }
        .to raise_error(ArgumentError, /got nil\.\.nil\z/)
    end

    it 'names the type in the message' do
      expect { Class.new(FieldStruct::Base) { optional :site, :url, length: 0.5.. } }
        .to raise_error(ArgumentError, /\Alength: on URL takes a Range/)
    end

    it 'does not apply to non-string types' do
      expect { Class.new(FieldStruct::Base) { optional :count, :integer, length: 1..2 } }
        .to raise_error(ArgumentError, /\Alength: option does not apply to Integer fields/)
    end
  end
end
