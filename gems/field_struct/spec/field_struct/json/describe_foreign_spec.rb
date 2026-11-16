# frozen_string_literal: true

RSpec.describe 'as_json(describe_foreign: true) (FS-B105a)' do
  before do
    stub_const('Beacon', Class.new do
      attr_reader :id, :asked

      def initialize(id)
        @id = id
        @asked = 0
      end

      def as_json(*)
        @asked += 1
        { 'id' => id, 'lens_code' => 'L-3' }
      end
    end)
    stub_const('Lamp', Class.new(FieldStruct::Base) { optional :source, :value })
    stub_const('Lighthouse', Class.new(FieldStruct::Base) do
      optional :beacon, :value
      optional :spares, :value
      optional :lamp, Lamp
      optional :height_m, :value
    end)
  end

  let(:beacon) { Beacon.new(12) }
  let(:tower) do
    Lighthouse.new(beacon: beacon, spares: [Beacon.new(13), { 'east' => Object.new }, 'oil'],
                   lamp: Lamp.new(source: Beacon.new(14)), height_m: 3r)
  end

  it 'writes foreign objects as descriptions, nested structs included, and asks them nothing' do
    expect(tower.as_json(describe_foreign: true)).to eq(
      beacon: '#<Beacon id=12>', spares: ['#<Beacon id=13>', { 'east' => '#<Object>' }, 'oil'],
      lamp: { source: '#<Beacon id=14>' }, height_m: 3r
    )
    expect(beacon.asked).to eq(0)
  end

  it 'names an anonymous class #<anonymous>' do
    expect(Lamp.new(source: Class.new.new).as_json(describe_foreign: true)).to eq(source: '#<anonymous>')
  end

  it 'ends with the call, and leaves plain as_json and other options as they were' do
    tower.as_json(describe_foreign: true)
    expect(tower.as_json[:beacon]).to eq('id' => 12, 'lens_code' => 'L-3')
    expect(tower.as_json(only: :beacon)[:beacon]).to eq('id' => 12, 'lens_code' => 'L-3')
  end
end
