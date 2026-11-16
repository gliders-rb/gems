# frozen_string_literal: true

RSpec.describe 'Union picks for a Hash (FS-B83a, FS-B83b)' do
  before do
    stub_const('Mooring', Class.new(FieldStruct::Base) { required :berth, :string })
    stub_const('PontoonMooring', Class.new(FieldStruct::Base) do
      required :berth, :string
      required :pontoon, :string
    end)
    stub_const('Buoyed', Class.new(FieldStruct::Base) do
      required :buoy, :integer
      optional :berth, :string
    end)
  end

  describe 'the ordered scan (FS-B83a)' do
    let(:slip) do
      Class.new(FieldStruct::Base) { required :spot, :union, of: [Mooring, PontoonMooring, Buoyed] }
    end

    it 'stops at the first member that is valid with no unknown keys' do
      expect(slip.new(spot: { berth: 'C7' }).spot.class).to eq(Mooring)
    end

    it 'keeps going when a valid member would drop keys' do
      expect(slip.new(spot: { berth: 'C7', pontoon: 'north' }).spot.class).to eq(PontoonMooring)
    end

    it 'takes the valid member with the fewest unknown keys when none fits exactly' do
      pick = slip.new(spot: { 'buoy' => 3, 'berth' => 'C7', 'colour' => 'red' }).spot
      expect([pick.class, pick.buoy]).to eq([Buoyed, 3])
    end

    it 'ties go to the first declared' do
      expect(slip.new(spot: { berth: 'C7', colour: 'red' }).spot.class).to eq(Mooring)
    end

    it 'keeps the member with the fewest errors when none is valid, so its errors explain' do
      wide_first = Class.new(FieldStruct::Base) { required :spot, :union, of: [PontoonMooring, Mooring] }
      record = wide_first.new(spot: {})
      expect([record.spot.class, record.errors.to_h]).to eq([Mooring, { spot: ['is invalid'] }])
      expect(record.errors.paths).to eq('spot.berth' => ['is required'])
      expect(slip.new(spot: { pontoon: 'north' }).spot.class).to eq(Mooring) # one error each: the first declared
    end

    it 'skips a member that raises' do
      stub_const('StrictMooring', Class.new(FieldStruct::Base) do
        unknown_attributes :raise
        required :berth, :string
      end)
      strict = Class.new(FieldStruct::Base) { required :spot, :union, of: [StrictMooring, PontoonMooring] }
      expect(strict.new(spot: { berth: 'C7', pontoon: 'n' }).spot.class).to eq(PontoonMooring)
    end

    it 'tries non-struct members only when every struct member is out' do
      stub_const('StrictMooring', Class.new(FieldStruct::Base) do
        unknown_attributes :raise
        required :berth, :string
      end)
      stub_const('StrictPontoon', Class.new(PontoonMooring) { unknown_attributes :raise })
      loose = Class.new(FieldStruct::Base) { required :spot, :union, of: [:value, Mooring, PontoonMooring] }
      expect(loose.new(spot: { berth: 'C7' }).spot.class).to eq(Mooring)
      fallback = Class.new(FieldStruct::Base) { required :spot, :union, of: [StrictMooring, StrictPontoon, :value] }
      expect(fallback.new(spot: { tide: 'low' }).spot).to eq(tide: 'low')
    end

    it 'leaves scalars and instances as before' do
      mixed = Class.new(FieldStruct::Base) { optional :spot, :union, of: [:integer, Mooring, PontoonMooring] }
      expect(mixed.new(spot: '42').spot).to eq(42)
      given = PontoonMooring.new(berth: 'C7', pontoon: 'n')
      expect(mixed.new(spot: given).spot).to equal(given)
    end
  end

  describe 'discriminator: (FS-B83b)' do
    before do
      stub_const('Ferry', Class.new(FieldStruct::Base) do
        required :kind, :string, enum: %w[ferry]
        required :line, :string
      end)
      stub_const('Barge', Class.new(FieldStruct::Base) do
        required :kind, :symbol, enum: %i[barge tug]
        required :tonnes, :integer
      end)
    end

    let(:crossing) do
      Class.new(FieldStruct::Base) { required :craft, :union, of: [Ferry, Barge], discriminator: :kind }
    end

    it 'builds the member its tag names, String or Symbol' do
      expect(crossing.new(craft: { kind: 'ferry', line: 'Isle' }).craft.class).to eq(Ferry)
      expect(crossing.new(craft: { 'kind' => 'tug', 'tonnes' => 40 }).craft.class).to eq(Barge)
    end

    it 'picks by tag even when another member would fit better' do
      record = crossing.new(craft: { kind: 'barge', line: 'Isle' })
      expect([record.craft.class, record.errors.paths]).to eq([Barge, { 'craft.tonnes' => ['is required'] }])
    end

    it 'writes the tag back, since it is a declared field' do
      expect(crossing.new(craft: { kind: 'ferry', line: 'Isle' }).as_json).to eq(craft: { kind: 'ferry', line: 'Isle' })
    end

    it 'fails a missing or unknown tag with the declared tags only' do
      missing = crossing.new(craft: { line: 'Isle' })
      unknown = crossing.new(craft: { kind: 'raft-secret' })
      expect(missing.errors[:craft].first).to end_with('union discriminator kind is missing (expected one of ferry, barge, tug)')
      expect(unknown.errors[:craft].first).to end_with('union discriminator kind names no member (expected one of ferry, barge, tug)')
      expect(unknown.errors[:craft].first).not_to include('raft-secret')
    end

    it 'takes an explicit map and a default member' do
      tagged = Class.new(FieldStruct::Base) do
        required :craft, :union, of: [Ferry, Barge],
                                 discriminator: { field: :kind, map: { 'F' => Ferry, B: Barge }, default: Ferry }
      end
      expect(tagged.new(craft: { kind: 'B', tonnes: 3 }).craft.class).to eq(Barge)
      expect(tagged.new(craft: { kind: 'zz', line: 'Isle' }).craft.class).to eq(Ferry)
      expect(tagged.new(craft: { line: 'Isle' }).craft.class).to eq(Ferry)
    end

    describe 'at declaration' do
      def declare(of, discriminator)
        Class.new(FieldStruct::Base) { required :craft, :union, of: of, discriminator: discriminator }
      end

      it 'refuses each mistake with its own message' do
        stub_const('Raft', Class.new(FieldStruct::Base) { required :logs, :integer })
        stub_const('Skiff', Class.new(FieldStruct::Base) { required :kind, :string })
        stub_const('Punt', Class.new(FieldStruct::Base) { required :kind, :string, enum: %w[ferry] })
        {
          [[Ferry, Barge], 'kind'] => 'discriminator: on Union expects Symbol or Hash, got String ("kind")',
          [[Ferry, Barge], { fild: :kind }] => "discriminator: takes field:, map: and default:, got #{{ fild: :kind }.inspect}",
          [[Ferry, :string], :kind] => 'discriminator: needs every union member to be a FieldStruct class, got String',
          [[Ferry, Raft], :kind] => 'discriminator: :kind is not a field of Raft',
          [[Ferry, Skiff], :kind] => 'discriminator: :kind on Skiff needs enum: (or give the union a map:)',
          [[Ferry, Punt], :kind] => 'discriminator: :kind tag "ferry" names both Ferry and Punt',
          [[Ferry, Barge], { field: :kind, map: { 'r' => Raft } }] =>
            'discriminator: map: names Raft, which is not a member of this union',
          [[Ferry, Barge], { field: :kind, default: Raft }] =>
            'discriminator: default: names Raft, which is not a member of this union'
        }.each do |(of, discriminator), message|
          expect { declare(of, discriminator) }.to raise_error(ArgumentError, message)
        end
      end
    end
  end
end
