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
      # @param reads [Boolean] whether a mirror class reads other objects (a union member doesn't, FS-B167)
      def initialize(struct_class, reads: true)
        super()
        @struct_class = struct_class
        @reads = reads
      end

      # @param value [::Object] nil, an instance of the struct, a Hash, or for a mirror any source object
      # @return [FieldStruct::Base, nil] the same instance, or a new one built from the Hash or read from the source
      # @raise [TypeError] for anything else
      def coerce(value, **)
        return value if value.nil? || value.is_a?(struct_class)
        return build(value) if value.is_a?(::Hash)
        return build(read(value)) if @reads && struct_class.mirror?

        raise ::TypeError, "expected #{struct_class.display_name} or Hash, got #{value.class}"
      end

      # Internal: {#coerce} with the options as one Hash, no keyword splat (see Types::Base.positional_coerce?).
      #
      # @param value [::Object]
      # @param _options [::Hash{::Symbol=>::Object}] unused: this type takes no options
      # @return [FieldStruct::Base, nil]
      # @api private
      def coerce_positional(value, _options)
        coerce(value)
      end

      # @return [::Class] the struct class
      def ruby_type
        struct_class
      end

      private

      # One public reader per declared field, all checked before any is called (FS-B167).
      def read(source)
        names = struct_class.metadata.map(&:name)
        missing = names.reject { |name| source.respond_to?(name) }
        raise Rejection, ::ArgumentError.new(missing_readers(source, missing)) unless missing.empty?

        names.to_h { |name| [name, source.public_send(name)] }
      end

      def missing_readers(source, missing)
        label = source.class.name || source.class.inspect
        noun = missing.size == 1 ? 'reader' : 'readers'
        "#{struct_class.display_name} mirrors #{label}, but #{label} has no public #{noun} for #{missing.map(&:inspect).join(', ')}"
      end

      def build(hash)
        struct_class.new(hash)
      rescue ::ArgumentError, ::TypeError, ::RangeError => e
        raise Rejection, e
      end
    end
  end
end
