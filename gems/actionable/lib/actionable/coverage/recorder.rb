# frozen_string_literal: true

module Actionable
  module Coverage
    # Prepended onto +Action+'s singleton class: notes the outcome of every real +run+ of a named action.
    module Recorder
      # @return [Actionable::Result]
      def run(*, **)
        result = super
        Coverage.record(name, result.status, result.code) if name && result.is_a?(Result)
        result
      end
    end
  end
end
