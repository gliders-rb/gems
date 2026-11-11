# frozen_string_literal: true

module Actionable
  # The matcher shared by case steps and input dispatch.
  module ValueMatch
    # @param branch_value [Object] an Array (inclusion), a Regexp (match against the String form) or anything (==)
    # @param value [Object]
    # @return [Boolean]
    def self.matches?(branch_value, value)
      return branch_value.include?(value) if branch_value.is_a?(Array)
      return value.to_s.match?(branch_value) if branch_value.is_a?(Regexp)

      value == branch_value
    end
  end
end
