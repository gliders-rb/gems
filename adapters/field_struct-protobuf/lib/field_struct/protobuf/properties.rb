# frozen_string_literal: true

module FieldStruct
  module Protobuf
    # Property lists per (serialization, class), so a conversion does not rebuild the node tree of every field.
    # An entry remembers the Field objects and the +serialize+ mapping it was read from and is dropped as soon as
    # either changed (FS-B159), so a field added after registration still reaches the message and fails as before
    # (PB-B31). Entries are immutable and swapped whole, so readers need no lock.
    module Properties
      Entry = Struct.new(:list, :fields, :mapping)
      private_constant :Entry

      @entries = {}

      class << self
        # @param klass [::Class<FieldStruct::Base>]
        # @param serialization [::Symbol]
        # @return [::Array<FieldStruct::Introspection::Property>] the frozen list, shared between calls
        def for(klass, serialization)
          table = @entries[serialization]
          entry = table && table[klass]
          return entry.list if entry && fresh?(entry, klass.metadata, serialization)

          build(klass, serialization)
        end

        # @return [nil]
        def clear
          @entries = {}
          nil
        end

        private

        def fresh?(entry, metadata, serialization)
          return false unless entry.mapping.equal?(metadata.serialization(serialization))

          fields = entry.fields
          index = 0
          metadata.each do |field|
            return false unless fields[index].equal?(field)

            index += 1
          end
          index == fields.size
        end

        def build(klass, serialization)
          metadata = klass.metadata
          entry = Entry.new(
            FieldStruct::Introspection.properties(klass, serialization: serialization).freeze,
            metadata.to_a.freeze, metadata.serialization(serialization)
          )
          (@entries[serialization] ||= {}.compare_by_identity)[klass] = entry
          entry.list
        end
      end
    end
  end
end
