# frozen_string_literal: true

module FieldStruct
  module Types
    # A field whose value is itself a FieldStruct::Base. Built by the DSL; not registered under a name.
    class Nested < Base
      # Carries an ArgumentError, TypeError or RangeError raised by an inner +new+ out through the
      # setter untouched: errors inside a nested record are structural and bypass the parent's policy (FS-B31).
      class Rejection < FieldStruct::Error
        # @return [Exception] the original error
        attr_reader :original

        # @param original [Exception]
        def initialize(original)
          super(original.message)
          @original = original
        end
      end

      # @return [::Class] the nested struct class
      attr_reader :struct_class

      # @param struct_class [::Class] a +FieldStruct::Base+ subclass
      def initialize(struct_class)
        super()
        @struct_class = struct_class
      end

      # @param value [::Object] nil, an instance of the struct, or a Hash
      # @return [FieldStruct::Base, nil] the same instance, or a new one built from the Hash
      # @raise [TypeError] for anything else
      def coerce(value, **)
        return value if value.nil? || value.is_a?(struct_class)
        raise ::TypeError, "expected #{struct_class.display_name} or Hash, got #{value.class}" unless value.is_a?(::Hash)

        build(value)
      end

      # @return [::Class] the struct class
      def ruby_type
        struct_class
      end

      private

      def build(hash)
        struct_class.new(hash)
      rescue ::ArgumentError, ::TypeError, ::RangeError => e
        raise Rejection, e
      end
    end
  end
end
