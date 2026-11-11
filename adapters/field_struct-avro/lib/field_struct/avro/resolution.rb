# frozen_string_literal: true

module FieldStruct
  module Avro
    # Walks a (writer, reader) schema pair the way Avro resolution pairs fields and reports the pairs the avro gem
    # would silently misread (AV-B39), plus the reader fields the writer lacked (AV-B40).
    class Resolution
      # +problems+: the sentences of AV-B39. +lacking+: reader record full name to the Avro names of its fields the writer lacked.
      Result = Struct.new(:problems, :lacking)

      # The avro gem's identity adapter, which a type without a decoded logical type gets.
      IDENTITY = ::Avro::LogicalTypes::Identity

      # @param writer [::Avro::Schema]
      # @param reader [::Avro::Schema]
      # @return [Result]
      def self.call(writer, reader)
        new.call(writer, reader)
      end

      def initialize
        @problems = []
        @lacking = {}
        @seen = {}
      end

      # @param writer [::Avro::Schema]
      # @param reader [::Avro::Schema]
      # @return [Result]
      def call(writer, reader)
        walk(writer, reader, '')
        Result.new(@problems, @lacking)
      end

      private

      def walk(writer, reader, path)
        return union(writer, reader, path) if writer.type_sym == :union || reader.type_sym == :union
        return unless ::Avro::SchemaCompatibility.match_schemas(writer, reader)

        if writer.type_sym == reader.type_sym
          same_type(writer, reader, path)
        elsif decoded?(writer) || decoded?(reader)
          problem(path, name(writer), name(reader))
        end
      end

      def same_type(writer, reader, path)
        case reader.type_sym
        when :record then record(writer, reader, path)
        when :array then walk(writer.items, reader.items, "#{path}[]")
        when :map then walk(writer.values, reader.values, "#{path}{}")
        else problem(path, name(writer), name(reader)) unless name(writer) == name(reader)
        end
      end

      def record(writer, reader, path)
        return if @seen[[writer.fullname, reader.fullname]]

        @seen[[writer.fullname, reader.fullname]] = true
        written = writer.fields_hash
        @lacking[reader.fullname] = reader.fields.map(&:name).reject { |field| written.key?(field) }
        writer.fields.each do |field|
          other = reader.fields_hash[field.name]
          walk(field.type, other.type, [path, field.name].reject(&:empty?).join('.')) if other
        end
      end

      def union(writer, reader, path)
        if writer.type_sym == :union && reader.type_sym == :union
          writer.schemas.each { |branch| pair(branch, reader, path) }
        elsif writer.type_sym == :union
          from_union(writer, reader, path)
        else
          pair(writer, reader, path)
        end
      end

      def pair(branch, reader, path)
        match = reader.schemas.find { |candidate| ::Avro::SchemaCompatibility.match_schemas(branch, candidate) }
        walk(branch, match, path) if match
      end

      def from_union(writer, reader, path)
        matched = writer.schemas.select { |branch| ::Avro::SchemaCompatibility.match_schemas(branch, reader) }
        before = @problems.size
        matched.each { |branch| walk(branch, reader, path) }
        return unless @problems.size == before && decoded?(reader) && matched.any?

        @problems << "#{path}: written as a union with #{matched.map { |branch| name(branch) }.join(', ')}, " \
                     "read as #{name(reader)} outside one, which the avro gem fails to decode (keep the field optional)"
      end

      def decoded?(schema)
        !schema.type_adapter.equal?(IDENTITY)
      end

      def name(schema)
        return schema.type_sym.to_s unless decoded?(schema)
        return "decimal (scale #{schema.scale})" if schema.logical_type == 'decimal'

        schema.logical_type
      end

      def problem(path, written, read)
        @problems << "#{path}: written as #{written}, read as #{read}"
      end
    end
  end
end
