# frozen_string_literal: true

module FieldStruct
  module Avro
    # Decoding bytes written with another schema: parses the writer schema, refuses the pairs the avro gem would
    # misread (AV-B39) and gives the schema to read with, minus the fields the writer lacked (AV-B40).
    module Evolution
      module_function

      # @param entry [Entry] the class's schema entry
      # @param writer_schema [::Hash, ::String, ::Avro::Schema, nil]
      # @return [Array(::Avro::Schema, ::Avro::Schema)] the schemas to write-resolve and read with
      # @raise [::ArgumentError] for a bad writer schema or an incompatible change
      def schemas(entry, writer_schema)
        return [entry.parsed, entry.parsed] if writer_schema.nil?

        Cache.writer(writer_schema, entry)
      end

      # Parses and checks one writer schema text against a reader entry (cached by +Cache.writer+).
      #
      # @param text [::String] the writer schema as JSON
      # @param entry [Entry]
      # @return [Array(::Avro::Schema, ::Avro::Schema)]
      # @raise [::ArgumentError] for an invalid writer schema or an incompatible change
      def resolve(text, entry)
        writer = WriterSchema.parse(text)
        result = Resolution.call(writer, entry.parsed)
        refuse!(result.problems)
        [writer, reader(entry, result.lacking)]
      end

      # @param entry [Entry]
      # @param lacking [::Hash{::String=>::Array<::String>}]
      # @return [::Avro::Schema]
      def reader(entry, lacking)
        return entry.parsed if lacking.values.all?(&:empty?)

        ::Avro::Schema.parse(Oj.dump(Projection.call(entry.schema, lacking), mode: :compat))
      end

      # @param problems [::Array<::String>]
      # @return [void]
      def refuse!(problems)
        return if problems.empty?

        raise ::ArgumentError, "FieldStruct::Avro can't read these bytes: #{problems.join('; ')}. " \
                               'The avro gem would decode them as the wrong value, or fail; this is not a compatible schema change'
      end
    end
  end
end
