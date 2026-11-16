# frozen_string_literal: true

RSpec.describe 'Frozen results (AC-B#frozenresult)' do
  before do
    stub_const('Kettle', Class.new do
      attr_accessor :temp_c

      def initialize = @temp_c = 20
    end)
    stub_const('Brew', Class.new(FieldStruct::Base) do
      required :blend, :string
      optional :notes, :value
    end)
    stub_const('SteepTea', Class.new(Actionable::Action) do
      fails :too_cold, kettle_check: { min_c: 80 }
      output do
        required :brew, Brew
        optional :kettle, :value
        optional :steps_taken, :value
      end
      step :pour
      on_success :sign
      def pour
        @brew = Brew.new(blend: +'oolong', notes: [+'floral', { 'cup' => +'gaiwan' }])
        @kettle = Kettle.new
        @steps_taken = [+'warm', +'pour']
      end

      def sign = @result.message = 'steeped'
    end)
  end

  let(:result) { SteepTea.run }

  it 'freezes the result after the last hook, so hooks can still change it' do
    expect([result.frozen?, result.message]).to eq([true, 'steeped'])
    expect { result.message = 'later' }.to raise_error(FrozenError)
  end

  it 'freezes the plain data inside: output struct, its values, errors, history' do
    brew = result.output.brew
    frozen = [result.output, brew, brew.blend, brew.notes, brew.notes[1], brew.notes[1]['cup'],
              result.output.steps_taken, result.output.steps_taken[0], result.errors, brew.errors, result.history]
    expect(frozen.map(&:frozen?)).to all(be(true))
    expect { result.errors.add(:base, 'x') }.to raise_error(FrozenError)
    expect { result.output.steps_taken << 'stir' }.to raise_error(FrozenError)
  end

  it 'never freezes a foreign object' do
    kettle = result.output.kettle
    kettle.temp_c = 95
    expect([kettle.frozen?, kettle.temp_c]).to eq([false, 95])
  end

  it 'keeps answering: valid?, to_h, as_json, paths' do
    expect([result.valid?, result.output.valid?, result.to_h[:status], result.as_json[:code]]).to eq([true, true, :success, 'success'])
    expect(result.errors.paths).to eq({})
  end

  it 'gives a frozen copy from with, and leaves the original alone' do
    later = result.with(message: 'reheated')
    expect([later.frozen?, later.errors.frozen?, later.message, result.message]).to eq([true, true, 'reheated', 'steeped'])
  end

  it 'freezes failures with their metadata, and the :invalid_input result' do
    cold = Class.new(SteepTea) do
      step :check
      def check = fail!(:too_cold)
    end.run
    expect([cold.code, cold.frozen?, cold.metadata.frozen?, cold.metadata[:kettle_check].frozen?]).to eq([:too_cold, true, true, true])
    picky = Class.new(Actionable::Action) { input { required :cups, :integer } }.run
    expect([picky.code, picky.frozen?, picky.errors.frozen?]).to eq([:invalid_input, true, true])
  end

  it 'leaves a hand-built result unfrozen' do
    expect(Actionable::Failure.new(code: :spilt).frozen?).to be(false)
  end

  it 'adopts a frozen result assigned to @result as an unfrozen copy' do
    inner = SteepTea
    outer = Class.new(Actionable::Action) do
      step :borrow
      define_method(:borrow) do
        @result = inner.run
        halt!
      end
    end
    result = outer.run
    expect([result.success?, result.frozen?, result.message]).to eq([true, true, 'steeped'])
  end

  it 'freezes each item of run_each, not the batch' do
    batch = SteepTea.run_each([{}, {}])
    expect([batch.frozen?, batch.results.map(&:frozen?)]).to eq([false, [true, true]])
  end
end
