# frozen_string_literal: true

module FieldStruct
  module Avro
    # Which field defaults can be written into the schema (AV-B8): only a literal of the field's own Avro type.
    module Defaults
      # Returned when the default is not a usable literal (nil itself is a valid Avro default).
      NONE = ::Object.new.freeze

      # The method that judges a default for each Avro primitive.
      BY_TYPE = { 'boolean' => :boolean, 'long' => :long, 'double' => :double, 'string' => :string }.freeze

      module_function

      # @param field [FieldStruct::Field]
      # @param type [::Object] the field's Avro type
      # @return [::Object] the literal to write, or +NONE+
      def literal(field, type)
        default = field.default
        return NONE if default.nil?
        return enum(type, default) if type.is_a?(::Hash)

        method = BY_TYPE[type]
        method ? send(method, field, default) : NONE
      end

      # @param default [::Object]
      # @return [::Boolean, NONE]
      def boolean(_field, default)
        [true, false].include?(default) ? default : NONE
      end

      # @param default [::Object]
      # @return [::Integer, NONE]
      def long(_field, default)
        default.is_a?(::Integer) ? default : NONE
      end

      # @param default [::Object]
      # @return [::Float, NONE]
      def double(_field, default)
        return default.to_f if default.is_a?(::Integer)

        default.is_a?(::Float) && default.finite? ? default : NONE
      end

      # @param field [FieldStruct::Field]
      # @param default [::Object]
      # @return [::String, NONE]
      def string(field, default)
        type = field.type_instance
        return default.to_s if type.is_a?(Types::Symbol) && default.is_a?(::Symbol)
        return NONE if type.is_a?(Types::Binary) || !type.is_a?(Types::String)

        default.is_a?(::String) ? default : NONE
      end

      # @param type [::Hash]
      # @param default [::Object]
      # @return [::String, NONE]
      def enum(type, default)
        return NONE unless type['type'] == 'enum' && default.is_a?(::Symbol) && type['symbols'].include?(default.to_s)

        default.to_s
      end
    end
  end
end
