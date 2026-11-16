# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    # The schema cache (JS-B40..B43): one entry per (class, serialization, decimals form), each valid while the stamps of every class
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
      # @param decimals [::Symbol] +:to_json+ or +:string+
      # @param freeze [Boolean] return the deep-frozen schema itself instead of a fresh copy (JS-B44)
      # @return [::Hash{::String=>::Object}]
      def fetch(klass, serialization, decimals = :to_json, freeze: false)
        key = [klass, serialization, decimals]
        entry = @mutex.synchronize { @entries[key] }
        return hand_out(entry.schema, freeze) if entry&.fresh?(serialization)

        result = Builder.new(klass, serialization, decimals).build
        frozen = Copy.deep(result.schema, freeze: true)
        @mutex.synchronize { result.hooked ? @entries.delete(key) : @entries[key] = Entry.new(frozen, result.stamps) }
        hand_out(frozen, freeze)
      end

      # @return [void]
      def clear
        @mutex.synchronize { @entries.clear }
      end

      private

      def hand_out(frozen, freeze)
        freeze ? frozen : Copy.fresh(frozen)
      end
    end
  end
end
