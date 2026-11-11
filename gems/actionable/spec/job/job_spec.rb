# frozen_string_literal: true

require 'actionable/job'

RSpec.describe Actionable::Job do
  def failure(code, **metadata)
    Actionable::Failure.new(metadata: metadata, code: code)
  end

  def skip_result(code, **metadata)
    Actionable::Skipped.new(metadata: metadata, code: code)
  end

  describe 'AC-B#jobdisposition' do
    it 'ships a default list of permanent codes' do
      expect(described_class::DEFAULT_PERMANENT_CODES).to eq(%i[invalid_input invalid_output not_found])
    end

    it 'acknowledges a success and a skip alike' do
      expect(described_class.disposition(Actionable::Success.new)).to eq(:ack)
      expect(described_class.disposition(skip_result(:adrift))).to eq(:ack)
    end

    it 'drops a failure whose code is permanent' do
      expect(described_class.disposition(failure(:not_found))).to eq(:discard)
    end

    it 'retries every other failure' do
      expect(described_class.disposition(failure(:timeout))).to eq(:retry)
    end

    it 'accepts a caller-supplied permanent list' do
      expect(described_class.disposition(failure(:timeout), permanent: [:timeout])).to eq(:discard)
      expect(described_class.disposition(failure(:not_found), permanent: [])).to eq(:retry)
    end

    it 'disregards retry metadata while honor_retry is off' do
      expect(described_class.disposition(failure(:timeout, retry: false))).to eq(:retry)
    end
  end

  describe 'AC-B#jobhonor' do
    def honored(result, **) = described_class.disposition(result, honor_retry: true, **)

    it 'obeys a truthy retry hint ahead of a permanent code or a skip' do
      expect(honored(failure(:not_found, retry: true))).to eq(:retry)
      expect(honored(skip_result(:later, retry: true))).to eq(:retry)
    end

    it 'obeys a falsy retry hint: failures are dropped, skips acknowledged' do
      expect(honored(failure(:timeout, retry: false))).to eq(:discard)
      expect(honored(skip_result(:later, retry: nil))).to eq(:ack)
    end

    it 'treats hint-free results and successes the ordinary way' do
      expect(honored(failure(:timeout))).to eq(:retry)
      expect(honored(failure(:not_found))).to eq(:discard)
      expect(honored(skip_result(:later))).to eq(:ack)
      expect(honored(Actionable::Success.new)).to eq(:ack)
    end
  end

  describe 'AC-B#honormacro' do
    it 'is false by default' do
      expect(build_action.honor_retry_metadata?).to be(false)
    end

    it 'opts in, inherits by dynamic lookup and can be turned off in a subclass' do
      parent = build_action
      child = Class.new(parent)
      parent.honor_retry_metadata
      expect(child.honor_retry_metadata?).to be(true)
      off = Class.new(parent) { honor_retry_metadata(enabled: false) }
      expect(off.honor_retry_metadata?).to be(false)
      expect(Class.new(off).honor_retry_metadata?).to be(false)
    end

    it 'exists on Action once the adapter is loaded' do
      expect(Actionable::Action).to respond_to(:honor_retry_metadata, :honor_retry_metadata?)
    end
  end

  describe 'AC-B#retryfailure' do
    it 'exposes the result and words a failure' do
      error = Actionable::Job::RetryableFailure.new(failure(:timeout))
      expect(error.result.code).to eq(:timeout)
      expect(error.message).to eq('actionable run failed with retryable code :timeout')
    end

    it 'words a retried skip' do
      error = Actionable::Job::RetryableFailure.new(skip_result(:later))
      expect(error.message).to eq('actionable run skipped with retryable code :later')
    end
  end

  describe 'AC-B#mixin' do
    let(:job_class) { Class.new { include Actionable::Job::Mixin } }
    let(:job) { job_class.new }

    def action(&) = build_action(&)

    it 'returns the result on ack and stores it' do
      result = job.run_actionable(action { step(:sail) && nil }.tap { |a| a.define_method(:sail) { nil } })
      expect(result).to be_success
      expect(job.actionable_result).to equal(result)
    end

    it 'passes arguments through to run' do
      echo = action do
        input { required :n, :integer }
        output { required :n, :integer }
        step :sail
        def sail = (@n = input.n)
      end
      expect(job.run_actionable(echo, n: 3).output.n).to eq(3)
    end

    it 'returns (not raises) on a discard' do
      gone = action do
        step :sail
        def sail = fail!(:not_found)
      end
      expect(job.run_actionable(gone)).to be_failure
    end

    it 'raises RetryableFailure on a retry, keeping the result' do
      flaky = action do
        step :sail
        def sail = fail!(:timeout)
      end
      expect { job.run_actionable(flaky) }.to raise_error(Actionable::Job::RetryableFailure) { |e| expect(e.result.code).to eq(:timeout) }
      expect(job.actionable_result.code).to eq(:timeout)
    end

    it 'honors retry metadata only when the action opted in' do
      build = lambda do |opt_in|
        action do
          honor_retry_metadata if opt_in
          fails :not_found, 'x', retry: true
          step :sail
          def sail = fail!(:not_found)
        end
      end
      expect(job.run_actionable(build.call(false))).to be_failure
      expect { job.run_actionable(build.call(true)) }.to raise_error(Actionable::Job::RetryableFailure)
    end

    it 'does not ask a non-action class about honor_retry_metadata?' do
      fake = Class.new { def self.run(*) = Actionable::Success.new }
      expect(job.run_actionable(fake)).to be_success
    end

    it 'lets a genuine exception propagate unchanged' do
      kraken = action do
        step :sail
        def sail = raise(ArgumentError, 'real')
      end
      expect { job.run_actionable(kraken) }.to raise_error(ArgumentError, 'real')
    end

    it 'has an overridable actionable_permanent_codes' do
      job_class.define_method(:actionable_permanent_codes) { [:timeout] }
      flaky = action do
        step :sail
        def sail = fail!(:timeout)
      end
      expect(job.run_actionable(flaky)).to be_failure
    end

    it 'defaults actionable_permanent_codes to the constant' do
      expect(job.actionable_permanent_codes).to eq(described_class::DEFAULT_PERMANENT_CODES)
    end
  end

  describe 'AC-B#jobpure' do
    it 'does not pull in either queue gem' do
      lib = File.expand_path('../../lib', __dir__)
      out = IO.popen(['ruby', "-I#{lib}", '-e', "require 'actionable/job'; print defined?(ActiveJob).inspect"], &:read)
      expect(out).to eq('nil')
    end
  end
end
