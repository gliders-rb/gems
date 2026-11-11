# frozen_string_literal: true

module FieldStruct
  module Types
    # Replaces a preset Symbol in an options Hash by the preset's value.
    module PresetResolver
      # @param options [::Hash{::Symbol=>::Object}]
      # @param key [::Symbol] the option to resolve
      # @param presets [::Hash{::Symbol=>::Object}] preset name to value
      # @param label [::String] what the preset is for, used in the error message
      # @return [::Hash{::Symbol=>::Object}] a new Hash; non-Symbol values and absent keys pass through
      # @raise [ArgumentError] for an unknown preset name
      def self.call(options, key, presets, label:)
        value = options[key]
        return options unless value.is_a?(::Symbol)
        raise ::ArgumentError, "unknown #{label} preset #{value.inspect}. Available: #{presets.keys.inspect}" unless presets.key?(value)

        options.merge(key => presets.fetch(value))
      end
    end
  end
end
