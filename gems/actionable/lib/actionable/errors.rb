# frozen_string_literal: true

module Actionable
  # Base of everything this gem raises.
  class Error < StandardError; end

  # A misconfigured action; also used by the adapters.
  class DefinitionError < Error; end
end
