# frozen_string_literal: true

module Actionable
  # Per-run record of executed steps, produced only when measuring.
  class History
    # One executed step or hook.
    Step = Struct.new(:section, :name, :started_at, :duration, :code, :nested, keyword_init: true) do
      # @return [Hash{Symbol=>Object}] section, name (class name String for an action step), started_at (ISO 8601), duration, code, history
      def as_json(*)
        label = name.is_a?(Class) ? name.name : name
        json = {}
        json[:section] = section
        json[:name] = label
        json[:started_at] = started_at.utc.iso8601(6)
        json[:duration] = duration
        json[:code] = code
        json[:history] = nested&.as_json
        json
      end
    end

    # @return [Array<Step>]
    attr_reader :steps

    def initialize
      @steps = []
    end

    # @param step [Step]
    # @return [self]
    def <<(step)
      steps.push(step)
      self
    end

    # @return [Boolean]
    def empty?
      steps.none?
    end

    # @return [Float] the sum of the step durations, in seconds
    def took
      steps.sum(&:duration)
    end

    # @return [Array<Hash{Symbol=>Object}>]
    def as_json(*)
      steps.collect(&:as_json)
    end

    # @return [String] Oj compat-mode JSON
    def to_json(*)
      Oj.dump(as_json, mode: :compat)
    end
  end
end
