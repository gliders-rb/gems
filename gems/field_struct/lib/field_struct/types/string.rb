# frozen_string_literal: true

module FieldStruct
  module Types
    # Text. Coerces any non-nil value with +to_s+; +strict: true+ narrows what is accepted.
    class String < Base
      # What +String#strip+ removes: NUL, tab, LF, VT, FF, CR and space (no other Unicode whitespace).
      BLANK = /\A[\0\t\n\v\f\r ]*\z/
      private_constant :BLANK

      class << self
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}]
        def own_option_schema
          {
            format: option(type: [::Regexp, ::Symbol]),
            enum: option(type: ::Array),
            strict: option(type: [::TrueClass, ::FalseClass]),
            length: option(type: ::Range)
          }
        end
      end

      # @param value [::Object]
      # @param strict [Boolean, nil] accept only a String, Symbol, Integer or #to_str responder
      # @return [::String, nil]
      # @raise [TypeError] under +strict: true+ for any other class
      def coerce(value, strict: false, **)
        coerce_with(value, strict)
      end

      # Internal: {#coerce} with the options as one Hash, no keyword splat (see Types::Base.positional_coerce?).
      #
      # @param value [::Object]
      # @param options [::Hash{::Symbol=>::Object}]
      # @return [::String, nil]
      # @api private
      def coerce_positional(value, options)
        coerce_with(value, options[:strict])
      end

      # @param value [::Object]
      # @return [Boolean] true for nil, empty and whitespace-only text
      def missing?(value)
        return true if value.nil?
        # Broken bytes skip the fast path so strip decides what is raised, as it always did.
        return value.match?(BLANK) if value.instance_of?(::String) && value.encoding.ascii_compatible? && value.valid_encoding?

        value.respond_to?(:strip) && value.strip.empty?
      end

      # @return [::Class]
      def ruby_type
        ::String
      end

      private

      def coerce_with(value, strict)
        return nil if value.nil?

        refuse_strict(value) if strict && !strict_input?(value)
        value.to_s
      end

      def strict_input?(value)
        value.is_a?(::String) || value.is_a?(::Symbol) || value.is_a?(::Integer) || value.respond_to?(:to_str)
      end

      def refuse_strict(value)
        raise ::TypeError, 'String fields with strict: true expect a String, Symbol, Integer or an object ' \
                           "responding to #to_str, got #{class_phrase(value)}"
      end
    end
  end
end
