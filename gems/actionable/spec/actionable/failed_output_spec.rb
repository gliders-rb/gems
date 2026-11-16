# frozen_string_literal: true

RSpec.describe 'A failed output never serializes a live object (AC-B#failedoutput)' do
  before do
    stub_const('Kiln', Class.new do
      attr_reader :id, :touched

      def initialize(id)
        @id = id
        @touched = []
      end

      def as_json(*) = (@touched << :as_json) && { 'id' => id, 'firing_code' => 'k-77' }
      def to_h = (@touched << :to_h) && { id: id }
    end)
    stub_const('KilnView', Class.new(FieldStruct::Base) { required :id, :integer })
    stub_const('FireBatch', Class.new(Actionable::Action) do
      output do
        required :kiln, KilnView
        optional :spare, :value
        optional :racks, :value
        optional :note, :string
      end
      step :load
      def load
        @kiln = Kiln.new(4)
        @spare = Kiln.new(5)
        @racks = [Kiln.new(6), { 'shelf' => Kiln.new(7) }, 'top']
        @note = 'warm'
      end
    end)
  end

  def kilns(result)
    [result.output.kiln, result.output.spare, *result.output.racks.first(1)]
  end

  it 'describes live objects in as_json of an :invalid_output result, without calling them' do
    result = FireBatch.run
    expect(result.code).to eq(:invalid_output)
    expect(result.as_json[:output]).to eq(kiln: '#<Kiln id=4>', spare: '#<Kiln id=5>',
                                          racks: ['#<Kiln id=6>', { 'shelf' => '#<Kiln id=7>' }, 'top'], note: 'warm')
    expect(kilns(result).flat_map(&:touched)).to eq([])
  end

  it 'does the same in to_h and to_json' do
    result = FireBatch.run
    expect(result.to_h[:output]).to include(kiln: '#<Kiln id=4>', spare: '#<Kiln id=5>')
    expect(result.to_json).to include('"kiln":"#<Kiln id=4>"').and include('"note":"warm"')
    expect(result.to_json).not_to include('k-77')
    expect(kilns(result).flat_map(&:touched)).to eq([])
  end

  it 'covers a fail! result' do
    cracked = Class.new(FireBatch) do
      step :crack
      def crack = fail!(:cracked)
    end
    expect(cracked.run.as_json[:output]).to include(kiln: '#<Kiln id=4>')
  end

  it 'covers live objects in the metadata of a hand-built failure or skip' do
    [Actionable::Failure, Actionable::Skipped].each do |kind|
      result = kind.new(code: :cooled, metadata: { kiln: Kiln.new(8), hours: 6 })
      expect([result.as_json[:metadata], result.to_h[:metadata]]).to eq([{ kiln: '#<Kiln id=8>', hours: 6 }] * 2)
    end
  end

  it 'keeps a measured history as History#as_json' do
    measured = Class.new(FireBatch) { measure :all }
    result = measured.run
    expect([result.history.class, result.as_json[:history]]).to eq([Actionable::History, result.history.as_json])
  end

  it 'keeps the live object on the output itself, for inspection' do
    expect(FireBatch.run.output.kiln).to be_a(Kiln)
  end

  it 'writes #<Name> without an id, and #<anonymous> for an anonymous class' do
    stub_const('Ember', Class.new)
    result = Actionable::Failure.new(code: :cold, output: { spark: Ember.new, other: Class.new.new })
    expect(result.as_json[:output]).to eq(spark: '#<Ember>', other: '#<anonymous>')
  end

  it 'leaves a success alone' do
    plain = Class.new(Actionable::Action) do
      output { optional :spare, :value }
      step(:go)
      def go = @spare = Kiln.new(9)
    end
    expect(plain.run.as_json[:output]).to eq(spare: { 'id' => 9, 'firing_code' => 'k-77' })
  end
end
