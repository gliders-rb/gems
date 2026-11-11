# frozen_string_literal: true

module FieldStruct
  module Avro
    # The cached result of building a class's schema: the frozen Hash, the schema the avro gem parsed from it, and
    # the stamps of every struct class the walk read (AV-B50..AV-B52).
    class Entry
      # @return [::Hash{::String=>::Object}] deeply frozen, owned by the entry
      attr_reader :schema
      # @return [::Avro::Schema]
      attr_reader :parsed

      # @param schema [::Hash{::String=>::Object}] what the builder produced; copied, never kept
      # @param parsed [::Avro::Schema]
      # @param stamps [::Array<Stamp>]
      def initialize(schema, parsed, stamps)
        @schema = Entry.deep_copy(schema, freeze: true)
        @parsed = parsed
        @stamps = stamps.freeze
      end

      # @return [::Boolean] whether no walked class changed since the build
      def fresh?
        @stamps.all?(&:fresh?)
      end

      # @return [::Hash{::String=>::Object}] a fresh, unfrozen deep copy of the schema
      def schema_copy
        Entry.deep_copy(@schema, freeze: false)
      end

      # Copies Hashes, Arrays and Strings; other values are shared.
      #
      # @param value [::Object]
      # @param freeze [::Boolean] freeze every copied container
      # @return [::Object]
      def self.deep_copy(value, freeze:)
        copy = case value
               when ::Hash then value.to_h { |key, item| [deep_copy(key, freeze: freeze), deep_copy(item, freeze: freeze)] }
               when ::Array then value.map { |item| deep_copy(item, freeze: freeze) }
               when ::String then value.dup
               else return value
               end
        freeze ? copy.freeze : copy
      end
    end
  end
end
