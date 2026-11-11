# frozen_string_literal: true

require 'bigdecimal'
require 'date'
require 'json'

# Random Avro schemas and datums for them: mostly values the schema takes, some near its edges, some of the wrong
# shape. Draws from Kernel#rand, which the spec helper seeds with the RSpec seed.
class SchemaFuzz
  PRIMITIVES = %w[null boolean int long float double bytes string].freeze
  TIMESTAMPS = %w[timestamp-millis timestamp-micros timestamp-nanos].freeze
  # The Avro slot each kind takes in a union (logical types share their base type's slot).
  SLOTS = { 'int' => 'int', 'date' => 'int', 'long' => 'long', 'bytes' => 'bytes', 'decimal' => 'bytes',
            'string' => 'string', 'uuid' => 'string' }.freeze

  def initialize
    @names = 0
  end

  # @return [Hash, String, Array] a schema as JSON-ready Ruby
  def schema(depth = 0)
    kinds = %w[primitive primitive logical logical enum]
    kinds += %w[array map record record union union] if depth < 3
    send(kinds.sample, depth)
  end

  def primitive(_depth) = PRIMITIVES.sample

  def logical(_depth)
    case rand(5)
    when 0 then decimal_type
    when 1 then { 'type' => 'int', 'logicalType' => 'date' }
    when 2 then { 'type' => 'string', 'logicalType' => 'uuid' }
    else { 'type' => 'long', 'logicalType' => TIMESTAMPS.sample }
    end
  end

  def decimal_type
    precision = [1, 2, 4, 9, 18, 19, 38, 40, 60].sample
    { 'type' => 'bytes', 'logicalType' => 'decimal', 'precision' => precision, 'scale' => rand(0..[precision, 6].min) }
  end

  def enum(_depth)
    { 'type' => 'enum', 'name' => fresh('Hue'), 'symbols' => %w[amber umber ochre sienna].sample(rand(1..4)) }
  end

  def array(depth) = { 'type' => 'array', 'items' => schema(depth + 1) }
  def map(depth) = { 'type' => 'map', 'values' => schema(depth + 1) }

  def record(depth)
    fields = Array.new(rand(1..4)) { |i| { 'name' => "f#{i}_#{%w[comb wax nectar drone].sample}", 'type' => schema(depth + 1) } }
    { 'type' => 'record', 'name' => fresh('Cell'), 'fields' => fields }
  end

  def union(depth)
    members = []
    slots = []
    rand(1..4).times do
      member = schema(depth + 1)
      next if member.is_a?(Array)

      slot = slot(member)
      next if slots.include?(slot)

      slots << slot
      members << member
    end
    members.unshift('null') if rand < 0.5 && !slots.include?('null')
    members.empty? ? ['null'] : members
  end

  def slot(member)
    return member if member.is_a?(String)

    kind = member['type']
    return member['name'] if %w[record enum].include?(kind)

    SLOTS.fetch(member['logicalType'] || kind) { kind == 'long' ? 'long' : kind }
  end

  def fresh(base)
    @names += 1
    "#{base}#{@names}"
  end

  # A datum for a parsed schema.
  def datum(schema)
    return odd_value if rand < 0.12

    type = schema.type_sym
    COMPOSITE_DATUMS.include?(type) ? send(:"#{type}_datum", schema) : scalar_datum(schema, type)
  end

  COMPOSITE_DATUMS = %i[enum array map record union].freeze

  # The generator of each logical type, then of each plain type (`integer` and `decimal` take an argument).
  SCALAR_DATUMS = {
    'date' => :date, 'decimal' => :decimal, 'timestamp-millis' => :time, 'timestamp-micros' => :time,
    'timestamp-nanos' => :time, null: :nothing, boolean: :boolean, int: :int32, long: :int64, float: :float,
    double: :float, bytes: :binary, string: :text
  }.freeze

  def scalar_datum(schema, type)
    name = SCALAR_DATUMS[schema.logical_type] || SCALAR_DATUMS.fetch(type)
    name == :decimal ? decimal(schema) : send(name)
  end

  def nothing = nil
  def boolean = [true, false].sample
  def int32 = integer(31)
  def int64 = integer(63)

  def enum_datum(schema) = rand < 0.9 ? schema.symbols.sample.to_s : 'umbra'
  def array_datum(schema) = Array.new(rand(0..3)) { datum(schema.items) }
  def map_datum(schema) = Array.new(rand(0..3)) { [text_key, datum(schema.values)] }.to_h
  def union_datum(schema) = datum(schema.schemas.sample)

  def record_datum(schema)
    pairs = schema.fields.map { |field| [field.name, datum(field.type)] }
    case rand(20)
    when 0 then pairs.shuffle.to_h
    when 1 then pairs.to_h { |key, value| [key.to_sym, value] }
    when 2 then pairs.drop(1).to_h
    when 3 then pairs.to_h.merge('extra' => 1)
    else pairs.to_h
    end
  end

  def integer(bits)
    edge = [0, 1, -1, 63, 64, -64, -65, (2**(bits - 1)) - 1, -2**(bits - 1), 2**bits, -2**bits - 1, 2**64, 2**31, 2**63]
    rand < 0.3 ? edge.sample : rand((-2**(bits - 1))..((2**(bits - 1)) - 1)) >> rand(0..bits)
  end

  def float
    [0.0, -0.0, 1.5, -2.25, 1e-310, 3.4e38, 1e39, 1e300, Float::INFINITY, -Float::INFINITY, Float::NAN,
     rand * (10**rand(-10..10)), -rand * 1000].sample
  end

  def decimal(schema)
    value = BigDecimal("#{['', '-'].sample}#{decimal_text(schema.precision, schema.scale || 0)}")
    rand < 0.05 ? [BigDecimal('NaN'), BigDecimal('Infinity'), BigDecimal('-0'), value.to_f, value.to_i].sample : value
  end

  # Digits up to the precision (sometimes one past it), with up to the scale's places (sometimes one more).
  def decimal_text(precision, scale)
    digits = rand < 0.9 ? rand(1..precision) : precision + 1
    places = rand < 0.9 ? rand(0..scale) : scale + 1
    whole = Array.new(digits) { rand(10) }.join.sub(/\A0+(?=\d)/, '')
    places = [places, whole.size].min
    return whole if places.zero?

    int = whole[0...-places]
    "#{int.empty? ? '0' : int}.#{whole[-places..]}"
  end

  def date
    case rand(6)
    when 0 then Date.jd(rand(0..3_000_000))
    when 1 then Date.new(1582, 10, rand(1..4), Date::ITALY)
    when 2 then DateTime.new(2001, 2, 3, 4, 5, 6)
    else Date.new(rand(1900..2100), rand(1..12), rand(1..28))
    end
  end

  def time
    seconds = rand(-4_000_000_000..4_000_000_000)
    case rand(8)
    when 0 then Time.at(seconds, Rational(rand(1..(10**12)), 997), :nsec)
    when 1 then Time.at(seconds).getlocal('+05:30')
    when 2 then Time.at(2**40)
    when 3 then Time.at(-seconds, rand(10**9), :nsec).utc
    else Time.at(seconds, rand(10**6) * [1, 1000].sample, :nsec)
    end
  end

  def binary = Array.new(rand(0..12)) { rand(256) }.pack('C*')

  def text
    case rand(10)
    when 0 then 'plain'.encode('US-ASCII')
    when 1 then 'raw'.b
    when 2 then "\xC3\xA9t\xC3\xA9".b
    when 3 then 'só'.encode('ISO-8859-1')
    when 4 then "\xFF\xFE".dup.force_encoding('UTF-8')
    when 5 then 'hive'.encode('UTF-16LE')
    else ['', 'queen', 'abeja üñî', '蜂蜜', '🐝 swarm', 'x' * rand(0..200)].sample
    end
  end

  def text_key = rand < 0.95 ? text : %i[sym 7].sample

  def odd_value
    [nil, true, false, 0, -1, 2**40, 2**64, 1.25, Float::NAN, 'odd', :odd, [], [1], {}, { 'k' => 1 },
     BigDecimal('1.5'), Rational(3, 2), Date.new(2020, 1, 1), Time.at(0), Object.new, 'x'.b].sample
  end
end
