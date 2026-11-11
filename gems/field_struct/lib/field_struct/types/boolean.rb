# frozen_string_literal: true

module FieldStruct
  module Types
    # True or false. Reads true/false, 1/0, and strings from a vocabulary.
    class Boolean < Base
      # Words for the +:english+ preset.
      # @return [::Hash{::Symbol=>::Array<::String>}]
      ENGLISH = { truthy: %w[true yes y on 1].freeze, falsy: %w[false no n off 0].freeze }.freeze
      # Digits for the +:numeric+ preset.
      # @return [::Hash{::Symbol=>::Array<::String>}]
      NUMERIC = { truthy: ['1'].freeze, falsy: ['0'].freeze }.freeze
      # Named truthy/falsy word lists.
      # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Array<::String>}}]
      PRESETS = { english_yes_no: ENGLISH, english: ENGLISH, numeric: NUMERIC }.freeze

      class << self
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}]
        def own_option_schema
          { values: option(type: [::Hash, ::Symbol], presets: presets.keys) }
        end

        # @return [::Array<::String>] strings read as true when a field declares no +values:+
        def default_truthy
          %w[true 1]
        end

        # @return [::Array<::String>] strings read as false when a field declares no +values:+
        def default_falsy
          %w[false 0]
        end

        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}] preset name to +{truthy:, falsy:}+
        def presets
          PRESETS
        end

        # Turns a +values:+ preset Symbol into its Hash.
        #
        # @param options [::Hash{::Symbol=>::Object}]
        # @return [::Hash{::Symbol=>::Object}]
        # @raise [ArgumentError] for an unknown preset
        def resolve_options(options)
          PresetResolver.call(options, :values, presets, label: ':boolean values')
        end
      end

      # @param value [::Object]
      # @param values [::Hash{::Symbol=>::Array<::String>}, nil] +{truthy: [...], falsy: [...]}+ vocabulary for String input
      # @return [Boolean, nil]
      # @raise [ArgumentError] when the value is not in the vocabulary
      def coerce(value, values: nil, **)
        return nil if value.nil?
        return value if value.equal?(true) || value.equal?(false)
        return value == 1 if numeric_flag?(value)

        truthy, falsy = vocabulary(values)
        word = value.is_a?(::String) ? value.downcase : nil
        return truthy.include?(word) if (truthy + falsy).include?(word)

        refuse(value, truthy + falsy)
      end

      # @return [::Array<::Class>]
      def ruby_type
        [::TrueClass, ::FalseClass]
      end

      private

      def numeric_flag?(value)
        value.is_a?(::Numeric) && [0, 1].include?(value)
      end

      def vocabulary(values)
        truthy = values ? values[:truthy] : self.class.default_truthy
        falsy = values ? values[:falsy] : self.class.default_falsy
        [truthy, falsy].map { |words| Array(words).map { |word| word.to_s.downcase } }
      end

      def refuse(value, words)
        got = value.is_a?(::String) ? 'a String that is not one' : value.class
        listed = words.map(&:inspect).join(', ')
        raise ::ArgumentError, "Boolean fields expect true, false, 1, 0 or one of the strings #{listed}, got #{got}"
      end
    end
  end
end
