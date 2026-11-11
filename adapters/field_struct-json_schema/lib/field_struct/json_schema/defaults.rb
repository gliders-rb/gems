# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    # Which field defaults are already what +to_json+ writes (JS-B5), decided without coercing.
    module Defaults
      NONE = Object.new.freeze
      T = FieldStruct::Types
      CHECKS = [
        [T::Boolean, :boolean], [T::Integer, :integer], [T::Float, :float],
        [T::Symbol, :symbol], [T::String, :string], [T::Value, :value]
      ].freeze
      private_constant :CHECKS

      module_function

      # @param field [FieldStruct::Field]
      # @return [::Object] the JSON value of the default, or {NONE}
      def for(field)
        value = field.default
        return NONE if value.nil?

        _, check = CHECKS.find { |klass, _| field.type_instance.is_a?(klass) }
        check ? send(check, value) : NONE
      end

      # @return [::Object]
      def boolean(value) = [true, false].include?(value) ? value : NONE

      # @return [::Object]
      def integer(value) = value.is_a?(::Integer) ? value : NONE

      # @return [::Object]
      def symbol(value) = value.is_a?(::Symbol) ? value.to_s : NONE

      # @return [::Object]
      def string(value) = value.is_a?(::String) ? value : NONE

      # @return [::Object]
      def value(value) = json_value?(value) ? value : NONE

      # An Integer becomes a Float; only a finite Float is kept.
      #
      # @return [::Object]
      def float(value)
        return value.to_f if value.is_a?(::Integer)

        value.is_a?(::Float) && value.finite? ? value : NONE
      end

      # A JSON value: String, Integer, finite Float, true, false, nil, or an Array / String-keyed Hash of them.
      #
      # @param value [::Object]
      # @return [::Boolean]
      def json_value?(value)
        case value
        when nil, true, false, ::String, ::Integer then true
        when ::Float then value.finite?
        when ::Array then value.all? { |item| json_value?(item) }
        when ::Hash then json_object?(value)
        else false
        end
      end

      # @param value [::Hash]
      # @return [::Boolean]
      def json_object?(value)
        value.all? { |key, item| key.is_a?(::String) && json_value?(item) }
      end
    end
  end
end
