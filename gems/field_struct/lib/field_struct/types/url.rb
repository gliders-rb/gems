# frozen_string_literal: true

module FieldStruct
  module Types
    # A String that must look like a URL (http and https unless a preset says otherwise).
    class URL < String
      # Named formats the +format:+ option accepts.
      # @return [::Hash{::Symbol=>::Regexp}]
      PRESETS = {
        http: %r{\Ahttps?://[^\s/$.?#][^\s]*\z}i,
        https_only: %r{\Ahttps://[^\s/$.?#][^\s]*\z}i,
        any_scheme: %r{\A[a-z][a-z0-9+\-.]*://[^\s/$.?#][^\s]*\z}i
      }.freeze

      extend FormatPresets

      class << self
        # @return [::Hash{::Symbol=>::Regexp}] preset name to pattern
        def presets
          PRESETS
        end

        # @return [::Symbol] the preset used when a field declares no +format:+
        def fallback_preset
          :http
        end

        # @return [::String] how preset errors name this type
        def preset_caption
          ':url'
        end
      end
    end
  end
end
