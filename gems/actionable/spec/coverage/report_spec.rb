# frozen_string_literal: true

require_relative 'coverage_helper'

RSpec.describe Actionable::Coverage::Report do
  let(:coverage) { Actionable::Coverage }

  before do
    cov_action('RepA', fails: [:a], skips: [:s])
    cov_action('RepB')
    coverage.record('RepA', :success, :success)
    coverage.record('RepA', :failure, :a)
    coverage.record_stub('RepA', :skipped, :s)
    coverage.record('RepB', :success, :success)
  end

  after { coverage.reset_config! }

  describe 'AC-B#covreport' do
    it 'builds rows, with stubbed_only a subset of missing' do
      report = described_class.new
      expect(report.rows).to eq(
        [{ action: 'RepA', expected: %w[success failure:a skipped:s], reached: %w[success failure:a], missing: ['skipped:s'],
           stubbed_only: ['skipped:s'] },
         { action: 'RepB', expected: ['success'], reached: ['success'], missing: [], stubbed_only: [] }]
      )
      expect(report.totals).to eq(actions: 2, expected: 4, reached: 3, missing: 1)
      expect(report.to_h).to eq(actions: report.rows, totals: report.totals)
      expect(Oj.load(report.to_json, mode: :compat)['totals']).to eq('actions' => 2, 'expected' => 4, 'reached' => 3, 'missing' => 1)
    end

    it 'drops actions with no real run under only_observed' do
      cov_action('RepC')
      coverage.only_observed = true
      expect(described_class.new.rows.map { |r| r[:action] }).to eq(%w[RepA RepB])
    end

    it 'merges shard files from an Array or a glob' do
      Dir.mktmpdir do |dir|
        coverage.reset!
        coverage.record('RepA', :success, :success)
        coverage.write(File.join(dir, 'a.json'))
        coverage.reset!
        coverage.record('RepA', :failure, :a)
        coverage.write(File.join(dir, 'b.json'))
        coverage.reset!
        [[File.join(dir, '*.json')], [Dir[File.join(dir, '*.json')]]].each do |(files)|
          row = described_class.new(files: files).rows.first
          expect(row[:reached]).to eq(%w[success failure:a])
        end
      end
    end

    it 'raises for a glob matching nothing' do
      expect { described_class.new(files: '/nonexistent-dir/*.json') }
        .to raise_error(Actionable::Error, 'no coverage files match /nonexistent-dir/*.json')
    end
  end

  describe 'AC-B#covtext' do
    it 'prints a table of the gaps' do
      cov_action('RepLongName', fails: [:z])
      expect(described_class.new.to_s).to eq(
        [
          'Actionable outcome coverage',
          "  #{'Action'.ljust(11)}  #{'Never reached'.ljust(18)}  Stubbed only",
          "  #{'RepA'.ljust(11)}  #{''.ljust(18)}  skipped:s",
          "  #{'RepLongName'.ljust(11)}  success, failure:z",
          'Actions: 3  Expected outcomes: 6  Reached: 3  Missing: 3'
        ].join("\n")
      )
    end

    it 'says everything was reached when nothing is missing' do
      coverage.record('RepA', :skipped, :s)
      expect(described_class.new.to_s).to eq(<<~TEXT.chomp)
        Actionable outcome coverage
          every expected outcome was reached
        Actions: 2  Expected outcomes: 4  Reached: 4  Missing: 0
      TEXT
    end
  end

  describe 'AC-B#covbaseline and AC-B#covmessage' do
    def baseline_file(dir, content, ext = 'yml')
      File.join(dir, "baseline.#{ext}").tap { |path| File.write(path, content) }
    end

    it 'passes without a baseline whatever is missing' do
      report = described_class.new
      expect(report).to be_passed
      expect(report.baseline_message).to be_nil
    end

    it 'raises for a baseline path that does not exist' do
      coverage.baseline = '/adrift/baseline.yml'
      expect { described_class.new.passed? }.to raise_error(
        Actionable::Error, 'Coverage.baseline /adrift/baseline.yml does not exist; write it with Report#write_baseline'
      )
    end

    it 'passes when the gaps match the baseline (YAML and JSON)' do
      Dir.mktmpdir do |dir|
        coverage.baseline = baseline_file(dir, { 'RepA' => ['skipped:s'] }.to_yaml)
        expect(described_class.new).to be_passed
        coverage.baseline = baseline_file(dir, '{"RepA":["skipped:s"]}', 'json')
        expect(described_class.new).to be_passed
      end
    end

    it 'reports new gaps and stale entries with the documented message' do
      Dir.mktmpdir do |dir|
        path = baseline_file(dir, { 'RepB' => ['failure:old'], 'Gone' => ['success'] }.to_yaml)
        coverage.baseline = path
        report = described_class.new
        expect(report.new_gaps).to eq('RepA' => ['skipped:s'])
        expect(report.stale).to eq('RepB' => ['failure:old'], 'Gone' => ['success'])
        expect(report).not_to be_passed
        expect(report.baseline_message).to eq(<<~MSG.chomp)
          Actionable outcome coverage differs from the baseline in #{path}.
          New untested outcomes. Write a spec that reaches each one, or add it to the baseline:
            RepA: skipped:s
          Covered, or no longer declared. Remove each one from the baseline:
            RepB: failure:old
            Gone: success
          To rewrite the baseline from the current gaps, run the report with ACTIONABLE_COVERAGE_UPDATE_BASELINE=true.
        MSG
      end
    end

    it 'uses the configured hint' do
      Dir.mktmpdir do |dir|
        coverage.baseline = baseline_file(dir, {}.to_yaml)
        coverage.new_gap_hint = 'Fix:'
        expect(described_class.new.baseline_message).to include('New untested outcomes. Fix:')
      end
    end

    it 'does not judge an existing but unreported action under only_observed' do
      cov_action('RepQuiet', fails: [:q])
      coverage.only_observed = true
      Dir.mktmpdir do |dir|
        coverage.baseline = baseline_file(dir, { 'RepA' => ['skipped:s'], 'RepQuiet' => ['failure:q'] }.to_yaml)
        expect(described_class.new).to be_passed
      end
    end
  end

  describe 'AC-B#covbaselinewrite' do
    it 'exposes the gaps in baseline shape' do
      expect(described_class.new.to_baseline).to eq('RepA' => ['skipped:s'])
    end

    it 'writes YAML or pretty JSON with a trailing newline and returns the path' do
      Dir.mktmpdir do |dir|
        yml = File.join(dir, 'sub', 'b.yml')
        expect(described_class.new.write_baseline(yml)).to eq(yml)
        expect(YAML.safe_load_file(yml)).to eq('RepA' => ['skipped:s'])
        json = File.join(dir, 'b.json')
        described_class.new.write_baseline(json)
        text = File.read(json)
        expect(text).to end_with("}\n")
        expect(text).to include("\n  ")
        expect(Oj.load(text, mode: :compat)).to eq('RepA' => ['skipped:s'])
      end
    end

    it 'defaults to Coverage.baseline and raises with neither' do
      Dir.mktmpdir do |dir|
        coverage.baseline = File.join(dir, 'x.yml')
        described_class.new.write_baseline
        expect(File).to exist(File.join(dir, 'x.yml'))
      end
      coverage.baseline = nil
      expect { described_class.new.write_baseline }.to raise_error(
        ArgumentError, 'no baseline path given and Coverage.baseline is not set'
      )
    end
  end

  describe 'AC-B#covreportbang' do
    let(:io) { StringIO.new }

    around do |example|
      saved = ENV.to_h.slice('ACTIONABLE_COVERAGE_JSON', 'ACTIONABLE_COVERAGE_UPDATE_BASELINE')
      %w[ACTIONABLE_COVERAGE_JSON ACTIONABLE_COVERAGE_UPDATE_BASELINE].each { |k| ENV.delete(k) }
      example.run
    ensure
      %w[ACTIONABLE_COVERAGE_JSON ACTIONABLE_COVERAGE_UPDATE_BASELINE].each { |k| ENV.delete(k) }
      saved.each { |k, v| ENV[k] = v }
    end

    it 'prints the text and returns the report' do
      report = coverage.report!(io: io)
      expect(report).to be_a(described_class)
      expect(io.string).to eq("#{report}\n")
    end

    it 'writes JSON to ACTIONABLE_COVERAGE_JSON when set' do
      Dir.mktmpdir do |dir|
        ENV['ACTIONABLE_COVERAGE_JSON'] = File.join(dir, 'c.json')
        coverage.report!(io: io)
        expect(Oj.load(File.read(ENV.fetch('ACTIONABLE_COVERAGE_JSON')), mode: :compat)).to include('totals')
      end
    end

    it 'raises BaselineMismatch with the baseline message' do
      Dir.mktmpdir do |dir|
        coverage.baseline = File.join(dir, 'b.yml').tap { |p| File.write(p, {}.to_yaml) }
        expect { coverage.report!(io: io) }.to raise_error(Actionable::Coverage::BaselineMismatch, /differs from the baseline/)
        expect(Actionable::Coverage::BaselineMismatch.ancestors).to include(Actionable::Error)
      end
    end

    it 'rewrites the baseline instead when ACTIONABLE_COVERAGE_UPDATE_BASELINE is true' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'b.yml')
        File.write(path, {}.to_yaml)
        coverage.baseline = path
        ENV['ACTIONABLE_COVERAGE_UPDATE_BASELINE'] = 'true'
        coverage.report!(io: io)
        expect(io.string).to end_with("Actionable outcome coverage: wrote the baseline to #{path}\n")
        expect(YAML.safe_load_file(path)).to eq('RepA' => ['skipped:s'])
      end
    end

    it 'merges shard files' do
      Dir.mktmpdir do |dir|
        coverage.reset!
        coverage.record('RepA', :skipped, :s)
        coverage.write(File.join(dir, 's.json'))
        coverage.reset!
        coverage.report!(files: File.join(dir, '*.json'), io: io)
        expect(io.string).to include('RepA')
        expect(io.string).not_to include('skipped:s')
      end
    end
  end

  describe 'AC-B#covsuite' do
    let(:io) { StringIO.new }

    around do |example|
      saved = ENV.fetch('ACTIONABLE_COVERAGE_FILE', nil)
      ENV.delete('ACTIONABLE_COVERAGE_FILE')
      example.run
    ensure
      saved ? ENV['ACTIONABLE_COVERAGE_FILE'] = saved : ENV.delete('ACTIONABLE_COVERAGE_FILE')
    end

    it 'writes the shard and reports nothing when ACTIONABLE_COVERAGE_FILE is set' do
      Dir.mktmpdir do |dir|
        ENV['ACTIONABLE_COVERAGE_FILE'] = File.join(dir, 'shard.json')
        coverage.suite_finished(io: io)
        expect(io.string).to be_empty
        expect(coverage.read(ENV.fetch('ACTIONABLE_COVERAGE_FILE'))[:observed]).to include(['RepA', :success, :success])
      end
    end

    it 'prints a blank line then the report otherwise' do
      coverage.suite_finished(io: io)
      expect(io.string).to start_with("\nActionable outcome coverage\n")
    end

    it 'registers its after(:suite) hook once' do
      expect(coverage.suite_hook_registered?).to be(true)
    end
  end
end
