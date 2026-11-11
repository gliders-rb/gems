# frozen_string_literal: true

module Actionable
  module Coverage
    # What was reached, per action, against what each action declares; optionally judged against a baseline file.
    class Report
      # @param files [Array<String>, String] shard files, or a glob, merged into the current process's runs
      # @param observed [Set<Array(String, Symbol, Symbol)>] real runs
      # @param stubbed [Set<Array(String, Symbol, Symbol)>] stubbed runs
      # @raise [Actionable::Error] for a glob that matches nothing
      def initialize(files: [], observed: Coverage.observed, stubbed: Coverage.stubbed)
        @observed = observed.dup
        @stubbed = stubbed.dup
        merge_shards(files)
        @existing = Coverage.actions.map(&:name)
        @rows = build_rows
      end

      # @return [Array<Hash{Symbol=>Object}>] +{action:, expected:, reached:, missing:, stubbed_only:}+ per reported action
      attr_reader :rows

      # @return [Hash{Symbol=>Object}] +{actions:, expected:, reached:, missing:}+
      def totals
        { actions: rows.size, expected: sum(:expected), reached: sum(:reached), missing: sum(:missing) }
      end

      # @return [Hash{Symbol=>Object}]
      def to_h = { actions: rows, totals: totals }

      # @return [String]
      def to_json(*) = Oj.dump(to_h, mode: :compat)

      # @return [String] the human-readable report
      def to_s
        gaps = rows.reject { |row| row[:missing].empty? }
        body = gaps.empty? ? ['  every expected outcome was reached'] : table(gaps)
        total = totals
        ['Actionable outcome coverage', *body,
         "Actions: #{total[:actions]}  Expected outcomes: #{total[:expected]}  Reached: #{total[:reached]}  " \
         "Missing: #{total[:missing]}"].join("\n")
      end

      # @return [Hash{String=>Array<String>}] the current gaps in baseline shape
      def to_baseline
        rows.reject { |row| row[:missing].empty? }.to_h { |row| [row[:action], row[:missing]] }
      end

      # Writes the current gaps as the baseline (YAML for +.yml+ / +.yaml+, otherwise pretty JSON).
      #
      # @param path [String]
      # @return [String] the path
      # @raise [ArgumentError] with no path and no +Coverage.baseline+
      def write_baseline(path = Coverage.baseline)
        raise ArgumentError, 'no baseline path given and Coverage.baseline is not set' unless path

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, yaml?(path) ? to_baseline.to_yaml : "#{Oj.dump(to_baseline, mode: :compat, indent: 2).chomp}\n")
        path
      end

      # @return [Hash{String=>Array<String>}] current gaps the baseline does not list
      def new_gaps
        return {} unless Coverage.baseline

        known = baseline_data
        to_baseline.filter_map do |action, keys|
          fresh = keys - Array(known[action])
          [action, fresh] unless fresh.empty?
        end.to_h
      end

      # @return [Hash{String=>Array<String>}] baseline entries that name a missing action or an outcome that is no longer a gap
      def stale
        return {} unless Coverage.baseline

        current = to_baseline
        reported = rows.map { |row| row[:action] }
        baseline_data.filter_map do |action, keys|
          next [action, Array(keys)] unless @existing.include?(action)
          next unless reported.include?(action)

          old = Array(keys) - Array(current[action])
          [action, old] unless old.empty?
        end.to_h
      end

      # @return [Boolean] whether there are no new gaps and nothing stale (always true without a baseline)
      def passed?
        new_gaps.empty? && stale.empty?
      end

      # @return [String, nil] why the report differs from the baseline, nil when it passed
      def baseline_message
        return if passed?

        lines = ["Actionable outcome coverage differs from the baseline in #{Coverage.baseline}."]
        lines.push("New untested outcomes. #{Coverage.new_gap_hint}", *entries(new_gaps)) unless new_gaps.empty?
        lines.push('Covered, or no longer declared. Remove each one from the baseline:', *entries(stale)) unless stale.empty?
        lines << 'To rewrite the baseline from the current gaps, run the report with ACTIONABLE_COVERAGE_UPDATE_BASELINE=true.'
        lines.join("\n")
      end

      private

      def merge_shards(files)
        paths = files.is_a?(String) ? Dir.glob(files) : Array(files)
        raise Actionable::Error, "no coverage files match #{files}" if files.is_a?(String) && paths.empty?

        paths.each do |path|
          shard = Coverage.read(path)
          @observed.merge(shard[:observed])
          @stubbed.merge(shard[:stubbed])
        end
      end

      def build_rows
        found = Coverage.actions.map { |action| row_for(action) }
        found = found.select { |row| @observed.any? { |name, *| name == row[:action] } } if Coverage.only_observed
        found
      end

      def row_for(action)
        name = action.name
        expected = Coverage.expected_outcomes(action)
        reached = expected & keys_for(@observed, name)
        missing = expected - reached
        { action: name, expected: expected, reached: reached, missing: missing, stubbed_only: missing & keys_for(@stubbed, name) }
      end

      def keys_for(set, name)
        set.select { |action, *| action == name }.map { |_action, outcome, code| outcome == :success ? 'success' : "#{outcome}:#{code}" }
      end

      def sum(key) = rows.sum { |row| row[key].size }

      def table(gaps)
        cells = gaps.map { |row| [row[:action], (row[:missing] - row[:stubbed_only]).join(', '), row[:stubbed_only].join(', ')] }
        cells.unshift(['Action', 'Never reached', 'Stubbed only'])
        widths = cells.transpose.map { |column| column.map(&:length).max }
        cells.map { |row| "  #{row.each_with_index.map { |cell, i| cell.ljust(widths[i]) }.join('  ').rstrip}" }
      end

      def entries(hash) = hash.map { |action, keys| "  #{action}: #{keys.join(', ')}" }

      def yaml?(path) = %w[.yml .yaml].include?(File.extname(path))

      def baseline_data
        path = Coverage.baseline
        return {} unless path

        @baseline_data ||= {}
        @baseline_data[path] ||= load_baseline(path)
      end

      def load_baseline(path)
        raise Actionable::Error, "Coverage.baseline #{path} does not exist; write it with Report#write_baseline" unless File.exist?(path)

        text = File.read(path)
        (yaml?(path) ? YAML.safe_load(text) : Oj.load(text, mode: :compat)) || {}
      end
    end
  end
end
