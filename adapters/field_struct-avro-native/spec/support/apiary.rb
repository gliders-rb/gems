# frozen_string_literal: true

require 'bigdecimal'
require 'date'

# Struct classes covering every field type and Avro option the adapter maps, in a beekeeping vocabulary, plus random
# attribute Hashes for them. Draws from Kernel#rand (seeded by the spec helper).
module Apiary
  class Queen < FieldStruct::Base
    required :mark, :string
    required :born, :date
    optional :rating, :big_decimal, round: 1
  end

  class Frame < FieldStruct::Base
    required :slot, :integer
    required :weight, :big_decimal, round: 2
    optional :capped, :boolean
    optional :brood, :array, of: :integer
  end

  # A recursive named struct: an apiary yard holding sub-yards.
  class Yard < FieldStruct::Base
    required :label, :string
    optional :children, :array, of: Yard
  end

  class Hive < FieldStruct::Base
    required :id, :uuid
    required :name, :string
    required :count, :integer
    required :temp, :float
    required :honey, :big_decimal, round: 2
    required :ratio, :big_decimal, avro: { scale: 4, precision: 12 }
    required :raw_ratio, :big_decimal
    required :active, :boolean
    required :founded, :date
    required :checked_at, :time
    required :swarm_at, :time, avro: { timestamp: :nanos }
    required :fed_at, :time, avro: { timestamp: :millis }
    required :moved_at, :datetime
    required :notes, :value
    required :photo, :binary
    required :keeper, :email
    required :site, :url
    required :status, :symbol, enum: %i[strong weak queenless]
    required :mood, :symbol
    required :colour, :symbol, enum: %i[gold dark], avro: { enum_default: :gold }
    required :tags, :array, of: :string
    required :frames, :array, of: Frame
    required :queen, Queen
    optional :origin, :union, of: %i[integer string]
    optional :lineage, :union, of: [Queen, :integer]
    optional :inspector, Class.new(FieldStruct::Base) {
      required :initials, :string
      optional :visits, :integer
    }
    optional :temp_int, :integer, avro: { type: 'int' }
    optional :temp_f32, :float, avro: { type: 'float' }
    optional :meta, :value, avro: { type: { type: 'map', values: 'string' } }
    optional :yard, Yard
    optional :nickname, :string, default: 'bee'
    optional :stamped_at, :time, zone: 'America/Denver'
  end

  module Values
    module_function

    # @param precision [Symbol] the call's timestamp precision, for the time fields without their own
    def hive(precision = :micros)
      {
        id: uuid, name: words, count: integer, temp: float, honey: decimal(2), ratio: decimal(4, digits: 8),
        raw_ratio: decimal(rand(0..6)), active: [true, false].sample, founded: date, checked_at: time(precision),
        swarm_at: time(:nanos), fed_at: time(:millis), moved_at: time(precision).to_datetime, notes: json_value,
        photo: binary, keeper: "keeper#{rand(100)}@apiary.test", site: "https://apiary.test/#{rand(100)}",
        status: %i[strong weak queenless].sample, mood: %i[calm testy].sample, colour: %i[gold dark].sample,
        tags: Array.new(rand(1..3)) { words }, frames: Array.new(rand(1..4)) { frame }, queen: queen,
        **optional(precision)
      }
    end

    def optional(precision)
      {
        origin: [nil, integer, words].sample, lineage: [nil, queen, integer].sample,
        inspector: [nil, { initials: words[0, 2], visits: [nil, rand(50)].sample }].sample,
        temp_int: [nil, rand(INT32)].sample, temp_f32: [nil, 1.5, -0.25, 0.0, 1024.0].sample,
        **more_optional(precision)
      }.reject { |_, value| value.nil? && rand < 0.5 }
    end

    def more_optional(precision)
      { meta: [nil, { 'smoke' => words, 'veil' => words }].sample, yard: [nil, yard(2)].sample,
        nickname: [nil, '', words].sample, stamped_at: [nil, time(precision)].sample }
    end

    INT32 = (-2**31)..((2**31) - 1)

    def frame
      { slot: rand(1..20), weight: decimal(2), capped: [nil, true, false].sample, brood: [nil, Array.new(rand(3)) { integer }].sample }
    end

    def queen = { mark: %w[red blue green white yellow].sample, born: date, rating: [nil, decimal(1, digits: 2)].sample }
    def yard(depth) = { label: words, children: depth.zero? ? nil : Array.new(rand(0..2)) { yard(depth - 1) } }

    def uuid = [[8, 32], [4, 16], [4, 16], [4, 16], [12, 48]].map { |width, bits| rand(2**bits).to_s(16).rjust(width, '0') }.join('-')
    def words = ['comb', 'brood box', 'nectar flow', 'abeja reina', '蜂蜜', 'smoker 🐝'].sample(rand(1..2)).join(' ')
    def binary = Array.new(rand(1..16)) { rand(256) }.pack('C*')
    def date = Date.jd(rand(2_400_000..2_500_000))

    def integer
      [0, -1, 1, 2**62, -2**62, (2**63) - 1, -2**63, rand((-10**12)..(10**12)), rand(-100..100)].sample
    end

    def float
      [0.0, -0.0, 1.5, -273.15, 1e-300, 6.02e23, rand * 100, -rand].sample
    end

    def decimal(scale, digits: rand(1..30))
      unscaled = rand(10**digits) * [1, -1].sample
      BigDecimal(unscaled) / (BigDecimal(10)**scale)
    end

    UNITS = { micros: 1_000, nanos: 1, millis: 1_000_000 }.freeze

    def time(precision)
      seconds = rand(-2_000_000_000..4_000_000_000)
      nsec = rand((10**9) / UNITS.fetch(precision)) * UNITS.fetch(precision)
      t = Time.at(seconds, nsec, :nsec)
      [t, t.utc, t.getlocal('-06:00')].sample
    end

    def json_value
      [1, 'wax', [1, 'two', nil], { 'a' => { 'b' => [true, 25] } }, 'x' * 3].sample
    end
  end
end
