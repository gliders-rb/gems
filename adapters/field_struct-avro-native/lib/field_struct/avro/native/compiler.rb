# frozen_string_literal: true

module FieldStruct
  module Avro
    module Native
      # Turns a parsed +Avro::Schema+ into the flat node list +Plan.new+ takes, or +nil+ for a schema with a shape the
      # native encoder does not cover (then every encode with it runs the pure path).
      #
      # Each node is an Array starting with a tag; child nodes are referenced by index, so a recursive record is a
      # node that points back at itself.
      class Compiler
        # @return [Hash{Symbol => Integer}] the tag number of each node kind
        TAGS = {
          null: 0, boolean: 1, int: 2, long: 3, float: 4, double: 5, bytes: 6, string: 7,
          decimal: 8, date: 9, timestamp: 10, enum: 11, array: 12, map: 13, record: 14, union: 15
        }.freeze

        # Ticks per second of each timestamp logical type.
        #
        # @return [Hash{String => Integer}]
        TICKS = { 'timestamp-millis' => 1_000, 'timestamp-micros' => 1_000_000, 'timestamp-nanos' => 1_000_000_000 }.freeze

        # The logical types written with a conversion; any other logical type must use the identity adapter.
        #
        # @return [Hash{String => Array(Symbol, String)}] base type and adapter name
        CONVERTED = {
          'decimal' => [:bytes, 'BytesDecimal'], 'date' => [:int, 'IntDate'],
          'timestamp-millis' => [:long, 'TimestampMillis'], 'timestamp-micros' => [:long, 'TimestampMicros'],
          'timestamp-nanos' => [:long, 'TimestampNanos']
        }.freeze

        # @return [Array<Symbol>]
        PRIMITIVES = %i[null boolean int long float double bytes string].freeze
        # @return [Array<Symbol>]
        COMPOSITES = %i[record enum array map union].freeze

        # Raised inside the walk for a shape with no native encoding.
        class Unsupported < StandardError; end

        # @param schema [::Object] a parsed +Avro::Schema+
        # @return [Array(::Array<::Array<::Object>>, ::Integer), nil] the nodes and the root index, or nil when unsupported
        def self.call(schema)
          compiler = new
          root = compiler.index(schema)
          [compiler.nodes, root]
        rescue Unsupported
          nil
        end

        # @return [::Array<::Array<::Object>>]
        attr_reader :nodes

        def initialize
          @nodes = []
          @seen = {}.compare_by_identity
        end

        # @param schema [::Object] a parsed +Avro::Schema+
        # @return [::Integer] the node index of the schema, compiling it on first sight
        def index(schema)
          found = @seen[schema]
          return found if found

          at = @nodes.size
          @seen[schema] = at
          @nodes << nil
          @nodes[at] = node(schema)
          at
        end

        private

        def node(schema)
          type = schema.type_sym
          return primitive(schema, type) if PRIMITIVES.include?(type)
          raise Unsupported unless COMPOSITES.include?(type)

          [TAGS.fetch(type), send(type, schema)]
        end

        def record(schema) = schema.fields.map { |field| [field.name.to_s, index(field.type)] }
        def enum(schema) = schema.symbols.map(&:to_s)
        def array(schema) = index(schema.items)
        def map(schema) = index(schema.values)
        def union(schema) = schema.schemas.map { |member| index(member) }

        def primitive(schema, type)
          logical = schema.logical_type
          return [TAGS.fetch(type)] if logical.nil? || identity?(schema)

          base, adapter = CONVERTED[logical]
          raise Unsupported unless base == type && adapter?(schema.type_adapter, ::Avro::LogicalTypes.const_get(adapter))

          converted(schema, logical)
        end

        def converted(schema, logical)
          case logical
          when 'decimal' then decimal(schema)
          when 'date' then [TAGS[:date]]
          else [TAGS[:timestamp], TICKS.fetch(logical)]
          end
        end

        def decimal(schema)
          precision = schema.precision
          scale = schema.scale || 0
          raise Unsupported unless precision.is_a?(::Integer) && precision.positive? && scale.is_a?(::Integer) && scale >= 0

          [TAGS[:decimal], precision, scale]
        end

        # The avro gem keeps some adapters as modules and builds others per schema (decimal).
        def adapter?(adapter, expected)
          adapter.equal?(expected) || adapter.instance_of?(expected)
        end

        def identity?(schema)
          schema.type_adapter.equal?(::Avro::LogicalTypes::Identity)
        end
      end
    end
  end
end
