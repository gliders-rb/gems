# frozen_string_literal: true

RSpec.describe 'Error paths on an :invalid_input result (AC-B#invalidinput, FS-B40a)' do
  before do
    stub_const('Rung', Class.new(FieldStruct::Base) { required :height, :integer })
    stub_const('RaiseLadder', Class.new(Actionable::Action) do
      input do
        required :site, :string
        optional :rungs, :array, of: Rung
      end
      step :lean
      def lean = nil
    end)
  end

  it 'walks the input, while errors.to_h stays as it was' do
    result = RaiseLadder.run(site: 'barn', rungs: [{ height: 30 }, {}])
    expect(result.code).to eq(:invalid_input)
    expect(result.errors.to_h).to eq(rungs: ['is invalid'])
    expect(result.errors.paths).to eq('rungs[1].height' => ['is required'])
  end

  it 'gives plain names for top-level fields' do
    expect(RaiseLadder.run(rungs: []).errors.paths).to eq('site' => ['is required'])
  end
end
