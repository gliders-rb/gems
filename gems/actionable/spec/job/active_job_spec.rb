# frozen_string_literal: true

require 'active_job'
require 'actionable/job'

# The adapter is pure Ruby (AC-B#jobpure); this lane only shows it works under a real ActiveJob backend.
RSpec.describe 'Job adapter under ActiveJob' do
  before do
    ActiveJob::Base.logger = Logger.new(nil)
    ActiveJob::Base.queue_adapter = :test
    { 'Flaky' => :timeout, 'GoneAction' => :not_found }.each do |const_name, outcome|
      stub_const(const_name, Class.new(Actionable::Action) do
        step :sail
        define_method(:sail) { fail!(outcome) }
      end)
    end
    stub_const('FlakyJob', Class.new(ActiveJob::Base) do
      include Actionable::Job::Mixin

      retry_on Actionable::Job::RetryableFailure, attempts: 3, wait: 0

      def perform(action_name)
        run_actionable(Object.const_get(action_name))
      end
    end)
  end

  it 'AC-B#retryfailure: a retryable failure is re-enqueued by retry_on' do
    FlakyJob.perform_now('Flaky')
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(1)
  end

  it 'AC-B#mixin: a discard finishes the job without a retry' do
    FlakyJob.perform_now('GoneAction')
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
  end
end
