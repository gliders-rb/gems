# frozen_string_literal: true

module FieldStruct
  module Avro
    # Turns the +writer_schema:+ argument of +decode+ into the JSON text and the schema the avro gem parsed (AV-B38).
    module WriterSchema
      module_function

      # @param value [::Hash, ::String, ::Avro::Schema] a Hash with String keys, a JSON String or a parsed schema
      # @return [::String] the schema as JSON text
      # @raise [::ArgumentError] for any other form
      def text(value)
        case value
        when ::Hash then Oj.dump(value, mode: :compat)
        when ::String then value
        when ::Avro::Schema then value.to_s
        else
          raise ::ArgumentError, 'FieldStruct::Avro.decode: writer_schema: expects a Hash, a JSON String or an Avro::Schema, ' \
                                 "got #{value.class}"
        end
      end

      # @param text [::String] JSON text
      # @return [::Avro::Schema]
      # @raise [::ArgumentError] when the text is not JSON or not a valid Avro schema
      def parse(text)
        ::Avro::Schema.parse(text)
      rescue ::StandardError => e
        raise ::ArgumentError, "FieldStruct::Avro.decode: writer_schema: isn't a valid Avro schema (#{e.class}: #{e.message})"
      end
    end
  end
end
