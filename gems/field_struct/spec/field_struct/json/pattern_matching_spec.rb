# frozen_string_literal: true

RSpec.describe 'FS-B116 pattern matching' do
  let(:bed) { Class.new(FieldStruct::Base) { optional :habitat, :string } }
  let(:klass) do
    bd = bed
    Class.new(FieldStruct::Base) do
      required :name, :string
      optional :height, :integer
      optional :border, bd
      optional :homes, :array, of: bd
      serialize :json, name: 'fullName'
    end
  end

  it 'deconstruct_keys(nil) gives all attributes under canonical names' do
    u = klass.new(name: 'A', height: 3)
    expect(u.deconstruct_keys(nil)).to eq(name: 'A', height: 3, border: nil, homes: nil)
  end

  it 'deconstruct_keys(array) slices; undeclared keys are absent' do
    u = klass.new(name: 'A', height: 3)
    expect(u.deconstruct_keys(%i[name nope])).to eq(name: 'A')
    expect(u.deconstruct_keys([])).to eq({})
  end

  it 'deconstruct gives the values in declaration order' do
    expect(klass.new(name: 'A', height: 3).deconstruct).to eq(['A', 3, nil, nil])
  end

  it 'matches hash and array patterns, recursing into nested structs' do
    u = klass.new(name: 'A', height: 3, border: { habitat: 'X' }, homes: [{ habitat: 'P' }, { habitat: 'Q' }])
    result = case u
             in { name: String => name, border: { habitat: } } then [name, habitat]
             end
    expect(result).to eq(%w[A X])
    found = case u
            in { homes: [*, { habitat: 'Q' } => hit, *] } then hit
            end
    expect(found.habitat).to eq('Q')
    arr = case u
          in [String => n, Integer => a, *] then [n, a]
          end
    expect(arr).to eq(['A', 3])
  end

  it 'does not use external names, descriptions or errors' do
    u = klass.new(height: 3)
    expect(u.deconstruct_keys(nil)).not_to have_key(:fullName)
    expect(u.deconstruct_keys(nil)).not_to have_key(:errors)
    expect(u).not_to be_valid
  end

  it 'works on frozen and immutable instances' do
    frozen = Class.new(klass) { frozen! }.new(name: 'A')
    immutable = Class.new(klass) { immutable! }.new(name: 'B')
    from_hash = case frozen
                in { name: } then name
                end
    from_array = case immutable
                 in [name, *] then name
                 end
    expect([from_hash, from_array]).to eq(%w[A B])
  end
end
