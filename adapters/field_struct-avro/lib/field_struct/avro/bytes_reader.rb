# frozen_string_literal: true

module FieldStruct
  module Avro
    # Reads one datum from Avro binary with the avro gem, turning every way the gem fails on bad bytes into one
    # error (AV-B37). The conversion into a struct is not covered: its errors are the adapter's own (AV-B45).
    module BytesReader
      # The hint when no writer schema was given.
      OWN_HINT = 'they end early, or were written with another schema (pass writer_schema: for bytes from an older one)'

      # The hint when one was given.
      WRITER_HINT = "they end early, or the writer schema given doesn't resolve against %<klass>s's (the cause says why)"

      module_function

      # @param klass [::Class] the struct class being decoded, for the message
      # @param bytes [::String]
      # @param writer [::Avro::Schema] the schema the bytes were written with
      # @param reader [::Avro::Schema] the class's schema
      # @param writer_given [::Boolean] whether the caller passed +writer_schema:+
      # @return [::Object] the datum the avro gem read
      # @raise [::ArgumentError] when the avro gem cannot read the bytes (the original error is the +cause+)
      def read(klass, bytes, writer, reader, writer_given:)
        decoder = ::Avro::IO::BinaryDecoder.new(StringIO.new(bytes))
        ::Avro::IO::DatumReader.new(writer, reader).read(decoder)
      rescue ::StandardError => e
        raise ::ArgumentError, refusal(klass, e, writer_given)
      end

      # The message for a failed read; the hint depends on whether the caller named a writer schema.
      def refusal(klass, error, writer_given)
        advice = writer_given ? format(WRITER_HINT, klass: klass) : OWN_HINT
        "FieldStruct::Avro can't decode these bytes as #{klass} (#{error.class.name}): #{advice}"
      end
    end
  end
end
