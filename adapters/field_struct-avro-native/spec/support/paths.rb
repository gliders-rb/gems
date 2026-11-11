# frozen_string_literal: true

require 'stringio'

# The two write paths side by side. `pure_*` runs the avro gem's writer (the method the native module wraps), so a
# spec can compare it with the native result in the same process.
module Paths
  module_function

  # @return [String, nil] what the native encoder writes, or nil when it hands the datum to the pure path
  def native_write(schema, datum)
    FieldStruct::Avro::Native.encode(schema, datum)
  end

  # The avro gem's binary writer alone.
  def pure_write(schema, datum)
    io = StringIO.new(''.b)
    Avro::IO::DatumWriter.new(schema).write(datum, Avro::IO::BinaryEncoder.new(io))
    io.string
  end

  # FieldStruct::Avro.encode with the original (pure) write step.
  def pure_encode(struct, timestamp: :micros)
    entry = FieldStruct::Avro::Cache.reader(struct.class, :avro, timestamp)
    datum = FieldStruct::Avro.to_datum(struct, timestamp: timestamp)
    FieldStruct::Avro.method(:write).super_method.call(entry.parsed, datum, struct)
  end

  # [:ok, bytes] or [:raised, class, message]
  def outcome
    [:ok, yield]
  rescue StandardError => e
    [:raised, e.class, e.message]
  end
end
