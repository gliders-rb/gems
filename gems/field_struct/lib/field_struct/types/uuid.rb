# frozen_string_literal: true

module FieldStruct
  module Types
    # A String that must look like a UUID (checked on assignment, not at coercion).
    class UUID < String
      # Named formats the +format:+ option accepts.
      # @return [::Hash{::Symbol=>::Regexp}]
      PRESETS = {
        any_version: /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/i,
        v4: /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/i,
        v7: /\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/i
      }.freeze

      extend FormatPresets

      class << self
        # @return [::Hash{::Symbol=>::Regexp}] preset name to pattern
        def presets
          PRESETS
        end

        # @return [::Symbol] the preset used when a field declares no +format:+
        def fallback_preset
          :any_version
        end

        # @return [::String] how preset errors name this type
        def preset_caption
          ':uuid'
        end
      end
    end
  end
end
