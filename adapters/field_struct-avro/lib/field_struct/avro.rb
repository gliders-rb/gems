# frozen_string_literal: true

require 'bigdecimal'
require 'stringio'
require 'avro'
require 'oj'
require 'field_struct'

unless defined?(FieldStruct::Introspection)
  raise LoadError, 'field_struct-avro needs FieldStruct::Introspection (field_struct >= 1.0.0.pre1); ' \
                   'upgrade field_struct or check that its version is loaded'
end

require_relative 'avro/version'
require_relative 'avro/check'
require_relative 'avro/options'
require_relative 'avro/trail'
require_relative 'avro/names'
require_relative 'avro/defaults'
require_relative 'avro/scalar_types'
require_relative 'avro/union_rules'
require_relative 'avro/site'
require_relative 'avro/stamp'
require_relative 'avro/entry'
require_relative 'avro/schema_builder'
require_relative 'avro/value_json'
require_relative 'avro/zone'
require_relative 'avro/datum_writer'
require_relative 'avro/datum_reader'
require_relative 'avro/bytes_reader'
require_relative 'avro/writer_schema'
require_relative 'avro/resolution'
require_relative 'avro/projection'
require_relative 'avro/evolution'
require_relative 'avro/cache'
require_relative 'avro/methods'

# The field_struct namespace.
module FieldStruct
  # Apache Avro for field_struct classes: record schemas, datums and the binary encoding.
  module Avro
    # The accepted precisions of +:time+ and +:datetime+ fields.
    # @return [::Array<::Symbol>]
    TIMESTAMPS = %i[micros nanos millis].freeze

    class << self
      # The Avro record schema of a struct class.
      #
      # @param klass [::Class<FieldStruct::Base>] a named +FieldStruct::Base+ subclass
      # @param serialization [::Symbol, ::String] the +serialize+ format whose names become Avro field names
      # @param timestamp [::Symbol] +:micros+, +:nanos+ or +:millis+
      # @return [::Hash{::String=>::Object}] a fresh Hash
      # @raise [::ArgumentError] for a bad argument, an unmappable field or a schema the avro gem rejects
      def schema(klass, serialization: :avro, timestamp: :micros)
        serialization = Check.call(klass, timestamp: timestamp, serialization: serialization)
        Cache.reader(klass, serialization, timestamp).schema_copy
      end

      # An instance as the Hash the avro gem writes.
      #
      # @param struct [FieldStruct::Base] an instance of a struct class
      # @param serialization [::Symbol, ::String]
      # @param timestamp [::Symbol]
      # @return [::Hash{::String=>::Object}]
      # @raise [::ArgumentError] for a bad argument or a value that cannot be written exactly
      def to_datum(struct, serialization: :avro, timestamp: :micros)
        serialization = Check.call(struct.class, timestamp: timestamp, serialization: serialization)
        DatumWriter.new(serialization, timestamp).struct(struct, Trail.root(struct.class))
      end

      # A struct built from a datum Hash.
      #
      # @param klass [::Class<FieldStruct::Base>] a +FieldStruct::Base+ subclass
      # @param datum [::Hash{::String=>::Object}] the Hash the avro gem reads
      # @param serialization [::Symbol, ::String]
      # @return [FieldStruct::Base]
      def from_datum(klass, datum, serialization: :avro)
        serialization = Check.call(klass, serialization: serialization)
        DatumReader.new(serialization).struct(klass, datum, Trail.root(klass))
      end

      # An instance as Avro binary (one datum, no header or container).
      #
      # @param struct [FieldStruct::Base]
      # @param serialization [::Symbol, ::String]
      # @param timestamp [::Symbol]
      # @return [::String] binary bytes
      def encode(struct, serialization: :avro, timestamp: :micros)
        klass = struct.class
        serialization = Check.call(klass, timestamp: timestamp, serialization: serialization)
        entry = Cache.reader(klass, serialization, timestamp)
        datum = DatumWriter.new(serialization, timestamp).struct(struct, Trail.root(klass))
        write(entry.parsed, datum, struct)
      end

      # A struct read from Avro binary, written with the class's own schema or an older one.
      #
      # @param klass [::Class<FieldStruct::Base>] a named +FieldStruct::Base+ subclass
      # @param bytes [::String]
      # @param writer_schema [::Hash{::String=>::Object}, ::String, ::Object, nil] the schema older bytes were written with: a Hash,
      #   a JSON String or a parsed +Avro::Schema+
      # @param serialization [::Symbol, ::String]
      # @param timestamp [::Symbol]
      # @return [FieldStruct::Base]
      def decode(klass, bytes, writer_schema: nil, serialization: :avro, timestamp: :micros)
        serialization = Check.call(klass, timestamp: timestamp, serialization: serialization, bytes: bytes)
        entry = Cache.reader(klass, serialization, timestamp)
        writer, reader = Evolution.schemas(entry, writer_schema)
        datum = BytesReader.read(klass, bytes, writer, reader, writer_given: !writer_schema.nil?)
        DatumReader.new(serialization).struct(klass, datum, Trail.root(klass))
      end

      # Forgets every cached schema, property list and checked writer schema. The cache keeps classes alive:
      # under code reloading call this on each reload.
      #
      # @return [nil]
      def clear_cache
        Cache.clear
      end

      private

      def write(parsed, datum, struct)
        io = StringIO.new(''.b)
        ::Avro::IO::DatumWriter.new(parsed).write(datum, ::Avro::IO::BinaryEncoder.new(io))
        io.string
      rescue ::Avro::IO::AvroTypeError
        raise unless struct.respond_to?(:valid?) && !struct.valid?

        raise ::ArgumentError, "FieldStruct::Avro can't encode an invalid #{struct.class}: #{struct.errors.full_messages.join('; ')}",
              cause: nil
      end
    end
  end
end
