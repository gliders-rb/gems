# frozen_string_literal: true

module Actionable
  @layout_token = Object.new

  class << self
    # Identity token that changes whenever a step is declared; a class
    # remembers the token its required-method list was built under.
    #
    # @return [Object]
    attr_reader :layout_token

    # Marks every remembered required-method list stale.
    #
    # @return [Object] the new token
    def layout_changed!
      @layout_token = Object.new
    end
  end
end
