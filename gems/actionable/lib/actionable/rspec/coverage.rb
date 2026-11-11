# frozen_string_literal: true

require 'oj'
require 'yaml'
require 'fileutils'
require_relative '../../actionable'

require_relative '../coverage/recorder'
require_relative '../coverage/settings'
require_relative '../coverage/outcomes'
require_relative '../coverage/shards'
require_relative '../coverage/report'

module Actionable
  # Outcome coverage: which declared outcomes of each action a test run actually reached.
  module Coverage
    # Raised when the outcomes differ from the baseline file.
    class BaselineMismatch < Actionable::Error; end

    @lock = Mutex.new
    @observed = Set.new
    @stubbed = Set.new
    @enabled = true

    class << self
      include Settings
      include Outcomes
      include Shards

      # @return [Set<Array(String, Symbol, Symbol)>] a copy of the real runs seen so far
      def observed = @lock.synchronize { @observed.dup }

      # @return [Set<Array(String, Symbol, Symbol)>] a copy of the stubbed runs seen so far
      def stubbed = @lock.synchronize { @stubbed.dup }

      # Notes one real run.
      #
      # @param name [String]
      # @param outcome [Symbol] +:success+, +:failure+ or +:skipped+
      # @param code [Symbol]
      # @return [void]
      def record(name, outcome, code)
        add(@observed, name, outcome, code)
      end

      # Notes one run answered by a stub (see {Actionable::RSpec::Stubs}).
      #
      # @param name [String]
      # @param outcome [Symbol]
      # @param code [Symbol]
      # @return [void]
      def record_stub(name, outcome, code)
        add(@stubbed, name, outcome, code)
      end

      # Forgets everything recorded.
      #
      # @return [void]
      def reset!
        @lock.synchronize do
          @observed.clear
          @stubbed.clear
        end
      end

      # @return [void]
      def enable! = (@enabled = true)

      # Recording becomes a no-op; the recorder stays installed.
      #
      # @return [void]
      def disable! = (@enabled = false)

      # @return [Boolean]
      def enabled? = @enabled

      # Builds the report, prints it, and checks it against the baseline (see the +ACTIONABLE_COVERAGE_*+ variables).
      #
      # @param files [Array<String>, String] shard files or a glob to merge in
      # @param io [IO]
      # @return [Actionable::Coverage::Report]
      # @raise [BaselineMismatch]
      def report!(files: [], io: $stdout)
        report = Report.new(files: files)
        io.puts report.to_s
        json_path = ENV.fetch('ACTIONABLE_COVERAGE_JSON', nil)
        File.write(json_path, report.to_json) if json_path && !json_path.empty?
        finish_baseline(report, io)
        report
      end

      # What the +after(:suite)+ hook does: write this process's shard, or print the report.
      #
      # @param io [IO]
      # @return [void]
      def suite_finished(io: $stdout)
        path = ENV.fetch('ACTIONABLE_COVERAGE_FILE', nil)
        return write(path) if path && !path.empty?

        io.puts
        report!(io: io)
      end

      # @return [Boolean] whether the suite hook was registered with RSpec
      def suite_hook_registered? = @suite_hook_registered ? true : false

      # Registers the suite hook once, when RSpec is loaded.
      #
      # @return [void]
      def register_suite_hook
        return if @suite_hook_registered || !defined?(::RSpec) || !::RSpec.respond_to?(:configure)

        ::RSpec.configure { |config| config.after(:suite) { Actionable::Coverage.suite_finished } }
        @suite_hook_registered = true
      end

      private

      def add(set, name, outcome, code)
        return if !@enabled || name.nil?

        @lock.synchronize { set << [name, outcome, code.to_sym] }
      end

      def finish_baseline(report, io)
        if ENV['ACTIONABLE_COVERAGE_UPDATE_BASELINE'] == 'true'
          path = report.write_baseline
          io.puts "Actionable outcome coverage: wrote the baseline to #{path}"
        elsif !report.passed?
          raise BaselineMismatch, report.baseline_message
        end
      end
    end
  end

  Action.singleton_class.send(:prepend, Coverage::Recorder)
  Coverage.register_suite_hook
end
