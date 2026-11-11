# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    # The schema cache (JS-B40..B43): one entry per (class, serialization), each valid while the stamps of every class
    # it covers still match. A schema that asked a type hook is never stored (JS-I7).
    class Cache
      # A stored schema (deep-frozen) and the stamps it was built under.
      Entry = Struct.new(:schema, :stamps) do
        # @param serialization [::Symbol]
        # @return [::Boolean]
        def fresh?(serialization)
          stamps.all? { |klass, stamp| stamp.current?(klass, serialization) }
        end
      end
      private_constant :Entry

      def initialize
        @mutex = Mutex.new
        @entries = {}
      end

      # @param klass [::Class]
      # @param serialization [::Symbol]
      # @return [::Hash{::String=>::Object}] a fresh deep copy
      def fetch(klass, serialization)
        key = [klass, serialization]
        entry = @mutex.synchronize { @entries[key] }
        return Copy.fresh(entry.schema) if entry&.fresh?(serialization)

        result = Builder.new(klass, serialization).build
        frozen = Copy.deep(result.schema, freeze: true)
        @mutex.synchronize { result.hooked ? @entries.delete(key) : @entries[key] = Entry.new(frozen, result.stamps) }
        Copy.fresh(frozen)
      end

      # @return [void]
      def clear
        @mutex.synchronize { @entries.clear }
      end
    end
  end
end
