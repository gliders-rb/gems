# frozen_string_literal: true

RSpec.describe 'json_omit' do
  let(:launch) do
    Class.new(FieldStruct::Base) do
      json_omit :unset
      optional :station, :string
      optional :payload_g, :integer
      optional :tethered, :boolean, default: true
      optional :burst_m, :integer
      optional :notes, :string, default: nil
      serialize :json, payload_g: 'payloadGrams'
    end
  end

  describe 'FS-B104a: the policy reader' do
    it 'reads :none on Base and on a class that never set it' do
      expect(FieldStruct::Base.json_omit).to eq(:none)
      expect(Class.new(FieldStruct::Base).json_omit).to eq(:none)
    end

    it 'returns the policy it sets' do
      klass = Class.new(FieldStruct::Base)
      expect(klass.json_omit(:unset)).to eq(:unset)
      expect(klass.json_omit).to eq(:unset)
    end

    it 'is inherited, and a child setting its own leaves the parent alone' do
      child = Class.new(launch)
      expect(child.json_omit).to eq(:unset)
      child.json_omit :none
      expect([child.json_omit, launch.json_omit]).to eq(%i[none unset])
    end

    it 'refuses an unknown policy at the macro call' do
      expect { Class.new(FieldStruct::Base) { json_omit :missing } }
        .to raise_error(ArgumentError, 'unknown json_omit policy :missing (expected one of [:none, :unset])')
    end
  end

  describe 'FS-B104a: :unset' do
    it 'leaves out fields not given and nil, and writes defaults' do
      expect(launch.new(station: 'Ridge').as_json).to eq(station: 'Ridge', tethered: true)
    end

    it 'writes a given nil as nil, under the mapped key' do
      expect(launch.new(payload_g: nil, burst_m: 9000).as_json).to eq(payloadGrams: nil, tethered: true, burst_m: 9000)
    end

    it 'counts a writer call after new as given' do
      record = launch.new
      record.station = nil
      expect(record.as_json).to eq(station: nil, tethered: true)
    end

    it 'applies to to_json' do
      expect(launch.new(burst_m: 31_000).to_json).to eq('{"tethered":true,"burst_m":31000}')
    end

    it 'lets a nested struct follow its own policy' do
      inner = launch
      outer = Class.new(FieldStruct::Base) do
        optional :flight, inner
        optional :crew, :string
      end
      expect(outer.new(flight: { station: 'Mesa' }).as_json).to eq(flight: { station: 'Mesa', tethered: true }, crew: nil)
    end
  end

  it 'FS-B104: :none writes every field' do
    plain = Class.new(launch) { json_omit :none }
    expect(plain.new.as_json.keys).to eq(%i[station payloadGrams tethered burst_m notes])
  end
end
