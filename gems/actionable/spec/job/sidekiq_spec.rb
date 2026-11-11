# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/testing'
require 'actionable/job'

# Sidekiq's inline testing mode runs a job in the calling thread with no Redis (AC-B#jobpure).
RSpec.describe 'Job adapter under Sidekiq' do
  before do
    Sidekiq::Testing.inline!
    stub_const('Flaky', Class.new(Actionable::Action) do
      step :sail
      def sail = fail!(:timeout)
    end)
    stub_const('GoneAction', Class.new(Actionable::Action) do
      step :sail
      def sail = fail!(:not_found)
    end)
    stub_const('Fine', Class.new(Actionable::Action))
    stub_const('RunnerJob', Class.new do
      include Sidekiq::Job
      include Actionable::Job::Mixin

      def perform(action_name) = run_actionable(Object.const_get(action_name))
    end)
  end

  after { Sidekiq::Testing.fake! }

  it 'AC-B#retryfailure: a retryable failure raises out of the job, so Sidekiq retries it' do
    expect { RunnerJob.perform_async('Flaky') }.to raise_error(Actionable::Job::RetryableFailure, /timeout/)
  end

  it 'AC-B#mixin: a permanent failure and a success both finish the job' do
    expect { RunnerJob.perform_async('GoneAction') }.not_to raise_error
    expect { RunnerJob.perform_async('Fine') }.not_to raise_error
  end
end
