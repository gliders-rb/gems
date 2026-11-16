# frozen_string_literal: true

RSpec.describe 'proto: keys and refusals that name a fix (PB-B1, PB-B2a, PB-B9)' do
  def descriptor(klass) = FieldStruct::Protobuf.file_descriptor(klass)

  it 'PB-B2a: reports a misspelled number: as itself, with a suggestion' do
    klass = define_struct('Typo') { required :line, :string, proto: { numbr: 1 } }
    expect { descriptor(klass) }
      .to raise_error(ArgumentError, 'Typo#line: proto: has no key numbr: (did you mean number:?); it takes number:')
  end

  it 'PB-B2a: refuses any other key, without a suggestion when nothing is close' do
    klass = define_struct('Packed') { required :stops, :string, proto: { number: 1, packed: true } }
    expect { descriptor(klass) }.to raise_error(ArgumentError, 'Packed#stops: proto: has no key packed:; it takes number:')
  end

  it 'PB-B2a: refuses a String key, since number: is a Symbol' do
    klass = define_struct('Quoted') { required :line, :string, proto: { 'number' => 1 } }
    expect { descriptor(klass) }
      .to raise_error(ArgumentError, 'Quoted#line: proto: has no key "number" (did you mean number:?); it takes number:')
  end

  it 'PB-B1: an unusable number says which numbers are usable' do
    klass = define_struct('Zero') { required :line, :string, proto: { number: 0 } }
    expect { descriptor(klass) }.to raise_error(
      ArgumentError, "Zero#line: 0 isn't a usable protobuf field number; use an Integer in 1..536870911, outside 19000..19999"
    )
  end

  it 'PB-B9: a union refusal offers a way out' do
    klass = define_struct('Fork') { required :pick, :union, of: %i[string integer], proto: { number: 1 } }
    expect { descriptor(klass) }.to raise_error(
      ArgumentError, "Fork#pick is a union, which field_struct-protobuf can't map yet; " \
                     'split it into one field per member type, or declare it :value (a google.protobuf.Value)'
    )
  end
end
