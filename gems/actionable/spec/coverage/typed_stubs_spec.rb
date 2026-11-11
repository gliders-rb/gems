# frozen_string_literal: true

require 'actionable/rspec'

RSpec.describe 'typed stubs' do
  describe 'AC-B#typedstubs' do
    it 'stub helpers return the action\'s own result classes' do
      klass = Class.new(Actionable::Action) do
        typed_outcomes
        fails(:no) { required :why, :string }
      end
      stub_const('StubTarget', klass)
      allow_actionable_failure(StubTarget, code: :no, output: { why: 'x' })
      result = StubTarget.run
      expect(result).to be_a(StubTarget::Failure)
      expect(result.why).to eq('x')
    end
  end
end
