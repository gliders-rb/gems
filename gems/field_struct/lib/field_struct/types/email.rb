# frozen_string_literal: true

module FieldStruct
  module Types
    # A String that must look like an email address.
    class Email < String
      # One DNS label, as a pattern source.
      # @return [::String]
      LABEL = '[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
      # Named formats the +format:+ option accepts.
      # @return [::Hash{::Symbol=>::Regexp}]
      PRESETS = {
        permissive: /\A[^@\s]+@[^@\s]+\z/,
        default: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/,
        strict: /\A[\w.+-]+@#{LABEL}(?:\.#{LABEL})+\z/
      }.freeze

      extend FormatPresets

      class << self
        # @return [::Hash{::Symbol=>::Regexp}] preset name to pattern
        def presets
          PRESETS
        end

        # @return [::Symbol] the preset used when a field declares no +format:+
        def fallback_preset
          :default
        end

        # @return [::String] how preset errors name this type
        def preset_caption
          ':email'
        end
      end
    end
  end
end
