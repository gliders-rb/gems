# frozen_string_literal: true

module FieldStruct
  module Types
    # Class-level behaviour shared by the string types that validate against a Regexp by default
    # (+uuid+, +url+, +email+). The extending class defines +presets+, +fallback_preset+ and +preset_caption+.
    module FormatPresets
      # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}] the string schema, with +format:+ listing this type's presets
      def own_option_schema
        { format: option(type: [::Regexp, ::Symbol], presets: presets.keys) }
      end

      # Replaces a +format:+ preset Symbol by its Regexp.
      #
      # @param options [::Hash{::Symbol=>::Object}]
      # @return [::Hash{::Symbol=>::Object}]
      # @raise [ArgumentError] for an unknown preset name
      def resolve_options(options, **)
        PresetResolver.call(options, :format, presets, label: "#{preset_caption} format")
      end

      # The Regexp written into a field's options when it declares no +format:+.
      #
      # @return [::Regexp]
      def default_format
        presets.fetch(fallback_preset)
      end
    end
  end
end
