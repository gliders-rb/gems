# frozen_string_literal: true

RSpec.describe 'A required nullable input field (FS-B34, AC-B#rbsrun)' do
  let(:close_hatch) do
    named_action('CloseHatch') do
      input do
        required :hatch, :string
        required :sealed_at, :integer, nullable: true
      end
      step :seal
      def seal = nil
    end
  end

  it 'runs with the keyword set to nil' do
    expect(close_hatch.run(hatch: 'aft', sealed_at: nil)).to be_success
  end

  it 'ends :invalid_input when the keyword is left out' do
    result = close_hatch.run(hatch: 'aft')
    expect([result.code, result.errors.to_h]).to eq([:invalid_input, { sealed_at: ['is required'] }])
  end

  it 'is a required keyword typed T? in the generated RBS' do
    expect(Actionable::RBS.generate(close_hatch)).to include('sealed_at: ::Integer?')
    expect(Actionable::RBS.generate(close_hatch)).not_to include('?sealed_at:')
  end

  it 'reserves given_fields as an output name, since Result inherits it' do
    expect { build_action { output { optional :given_fields, :array, of: :symbol } } }
      .to raise_error(Actionable::DefinitionError, /output field\(s\) :given_fields conflict/)
  end
end
