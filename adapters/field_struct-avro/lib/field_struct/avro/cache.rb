# frozen_string_literal: true

require 'monitor'

module FieldStruct
  module Avro
    # The process-wide cache (AV-B50..AV-B57): schema entries per (class, serialization, timestamp), property lists
    # per (class, serialization) and checked writer schemas. One monitor guards every write.
    module Cache
      # The most checked writer schemas kept; the oldest inserted goes first (AV-B55).
      WRITERS_MAX = 512

      # A property list and the stamp of the class it was read from.
      Props = Struct.new(:list, :stamp)

      @lock = Monitor.new
      @readers = {}
      @props = {}
      @writers = {}

      class << self
        # @param klass [::Class]
        # @param serialization [::Symbol]
        # @param timestamp [::Symbol]
        # @return [Entry] the class's schema entry, rebuilt when a class it walked changed
        def reader(klass, serialization, timestamp)
          key = [klass, serialization, timestamp]
          entry = @readers[key]
          return entry if entry&.fresh?

          @lock.synchronize do
            entry = @readers[key]
            return entry if entry&.fresh?

            replace_reader(key, SchemaBuilder.entry(klass, serialization, timestamp))
          end
        end

        # @param klass [::Class]
        # @param serialization [::Symbol]
        # @return [::Array<FieldStruct::Introspection::Property>] the frozen property list
        # @raise [::ArgumentError] when a field's +avro:+ option is not a Hash
        def properties(klass, serialization)
          key = [klass, serialization]
          cached = @props[key]
          return cached.list if cached&.stamp&.fresh?

          @lock.synchronize do
            cached = @props[key]
            return cached.list if cached&.stamp&.fresh?

            @props[key] = build_properties(klass, serialization)
            @props[key].list
          end
        end

        # @param writer_schema [::Hash, ::String, ::Avro::Schema] as given to +decode+
        # @param entry [Entry] the reader entry
        # @return [Array(::Avro::Schema, ::Avro::Schema)] the schemas to read with (see +Evolution+)
        def writer(writer_schema, entry)
          text = WriterSchema.text(writer_schema)
          key = [text.dup.freeze, entry]
          found = @writers[key]
          return found if found

          @lock.synchronize do
            @writers[key] ||= Evolution.resolve(text, entry)
            @writers.shift while @writers.size > Cache::WRITERS_MAX
            @writers.fetch(key) { Evolution.resolve(text, entry) }
          end
        end

        # @return [::Integer] how many checked writer schemas are held
        def writers_count
          @writers.size
        end

        # @return [nil]
        def clear
          @lock.synchronize do
            @readers.clear
            @props.clear
            @writers.clear
          end
          nil
        end

        private

        # @param key [::Array]
        # @param entry [Entry]
        # @return [Entry]
        def replace_reader(key, entry)
          old = @readers[key]
          @writers.delete_if { |(_, reader), _| reader.equal?(old) } if old
          @readers[key] = entry
        end

        # @param klass [::Class]
        # @param serialization [::Symbol]
        # @return [Props]
        def build_properties(klass, serialization)
          stamp = Stamp.of(klass, serialization)
          list = FieldStruct::Introspection.properties(klass, serialization: serialization)
          list.each { |prop| Options.read(prop.field) { "#{klass.name || klass.inspect}##{prop.field.name}" } }
          Props.new(list.freeze, stamp)
        end
      end
    end
  end
end
