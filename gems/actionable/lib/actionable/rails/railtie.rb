# frozen_string_literal: true

module Actionable
  # A no-op Railtie so Rails knows the gem; it configures nothing.
  class Railtie < ::Rails::Railtie; end
end
