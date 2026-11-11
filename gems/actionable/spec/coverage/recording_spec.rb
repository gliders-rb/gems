# frozen_string_literal: true

require_relative 'coverage_helper'

RSpec.describe Actionable::Coverage do
  describe 'AC-B#covload' do
    it 'is not loaded by the core or actionable/rspec' do
      lib = File.expand_path('../../lib', __dir__)
      out = IO.popen(['bundle', 'exec', 'ruby', "-I#{lib}", '-e', "require 'actionable/rspec'; print defined?(Actionable::Coverage).inspect"],
                     chdir: File.expand_path('../..', __dir__), &:read)
      expect(out).to eq('nil')
    end
  end

  describe 'AC-B#covrecord' do
    it 'records every real run of a named action as [name, outcome, code]' do
      ok = cov_action('CovOk')
      failing = cov_action('CovFail', fails: [:adrift]) { def sail = fail!(:adrift) }
      skipping = cov_action('CovSkip', skips: [:later]) { def sail = skip!(:later) }
      [ok, failing, skipping].each(&:run)
      expect(described_class.observed).to eq(
        Set[['CovOk', :success, :success], ['CovFail', :failure, :adrift], ['CovSkip', :skipped, :later]]
      )
    end

    it 'records nested action steps and run_each items' do
      child = cov_action('CovChild')
      parent = cov_action('CovParent') { step child }
      parent.run
      child.run_each([{}, {}])
      expect(described_class.observed.map(&:first).uniq).to contain_exactly('CovChild', 'CovParent')
    end

    it 'records the invalid_input failure of a run that ends before the runner' do
      klass = cov_action('CovTyped') { input { required :n, :integer } }
      klass.run
      expect(described_class.observed).to include(['CovTyped', :failure, :invalid_input])
    end

    it 'ignores anonymous classes' do
      build_action { step(:sail) && nil }.tap { |a| a.define_method(:sail) { nil } }.run
      expect(described_class.observed).to be_empty
    end

    it 'ignores non-Result return values' do
      klass = cov_action('CovOdd')
      allow(klass).to receive(:run).and_return(:adrift)
      klass.run
      expect(described_class.observed).to be_empty
    end

    it 'does not count a stubbed run as real and keeps the gem stub helpers in the stubbed set' do
      klass = cov_action('CovStubbed', fails: [:kraken])
      allow_actionable_failure(klass, code: :kraken)
      klass.run
      expect(described_class.observed).to be_empty
      expect(described_class.stubbed).to eq(Set[['CovStubbed', :failure, :kraken]])
    end

    it 'returns copies from observed and stubbed' do
      described_class.record('X', :success, :success)
      described_class.observed << :junk
      described_class.stubbed << :junk
      expect(described_class.observed).to eq(Set[['X', :success, :success]])
      expect(described_class.stubbed).to be_empty
    end

    it 'records through record and record_stub, deduplicated, and reset! clears' do
      2.times { described_class.record('A', :failure, :x) }
      described_class.record_stub('A', :skipped, :y)
      expect(described_class.observed.size).to eq(1)
      expect(described_class.stubbed.size).to eq(1)
      described_class.reset!
      expect(described_class.observed).to be_empty
    end

    it 'is a no-op while disabled, with the recorder still installed' do
      klass = cov_action('CovOff')
      expect(described_class).to be_enabled
      described_class.disable!
      klass.run
      described_class.record('B', :success, :success)
      described_class.record_stub('B', :success, :success)
      expect(described_class.observed).to be_empty
      expect(described_class.stubbed).to be_empty
      expect(described_class).not_to be_enabled
      described_class.enable!
      klass.run
      expect(described_class.observed.size).to eq(1)
    end

    it 'is safe under concurrent writers' do
      threads = Array.new(4) { |i| Thread.new { 50.times { |j| described_class.record("T#{i}", :failure, :"c#{j}") } } }
      threads.each(&:join)
      expect(described_class.observed.size).to eq(200)
    end
  end

  describe 'AC-B#covsettings' do
    it 'has these defaults' do
      expect(described_class.root).to eq(Actionable::Action)
      expect(described_class.include_prefixes).to eq([])
      expect(described_class.exclude_prefixes).to eq([])
      expect(described_class.gem_codes).to eq([])
      expect(described_class.only_observed).to be(false)
      expect(described_class.baseline).to be_nil
      expect(described_class.loader).to be_nil
      expect(described_class.new_gap_hint).to eq('Write a spec that reaches each one, or add it to the baseline:')
      expect(described_class::DEFAULT_NEW_GAP_HINT).to eq(described_class.new_gap_hint)
    end

    it 'accepts Symbols and Strings for gem_codes' do
      described_class.gem_codes = ['invalid_input', :invalid_output]
      expect(described_class.gem_codes).to eq(%i[invalid_input invalid_output])
    end

    it 'refuses any other gem code' do
      expect { described_class.gem_codes = [:kraken] }.to raise_error(
        ArgumentError, 'not a gem failure code: :kraken (the gem emits :invalid_input, :invalid_output)'
      )
    end

    it 'reset_config! restores every setting' do
      described_class.root = Class
      described_class.include_prefixes = ['A']
      described_class.exclude_prefixes = ['B']
      described_class.loader = -> {}
      described_class.gem_codes = [:invalid_input]
      described_class.only_observed = true
      described_class.baseline = 'x.yml'
      described_class.new_gap_hint = 'hi'
      described_class.reset_config!
      expect([described_class.root, described_class.include_prefixes, described_class.exclude_prefixes, described_class.loader,
              described_class.gem_codes, described_class.only_observed, described_class.baseline, described_class.new_gap_hint])
        .to eq([Actionable::Action, [], [], nil, [], false, nil, described_class::DEFAULT_NEW_GAP_HINT])
    end
  end

  describe 'AC-B#covshards' do
    it 'writes sorted string triples with a version and reads them back as Symbols' do
      described_class.record('B', :failure, :z)
      described_class.record('A', :success, :success)
      described_class.record_stub('A', :skipped, :s)
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'deep', 'shard.json')
        described_class.write(path)
        raw = Oj.load(File.read(path), mode: :compat)
        expect(raw).to eq('version' => 1, 'observed' => [%w[A success success], %w[B failure z]],
                          'stubbed' => [%w[A skipped s]])
        expect(described_class.read(path)).to eq(observed: Set[['A', :success, :success], ['B', :failure, :z]],
                                                 stubbed: Set[['A', :skipped, :s]])
      end
    end
  end
end
