# frozen_string_literal: true

# The internal positional entry gives exactly what coerce gives, and steps aside when coerce is overridden.
RSpec.describe 'positional coerce' do
  def outcome
    [:ok, yield]
  rescue ArgumentError, TypeError, RangeError => e
    [e.class, e.message]
  end

  cases = {
    integer: [[{}, '17'], [{ base: 16 }, 'ff'], [{ strict: true }, 3.5], [{ strict: true }, '8'], [{}, 'tall']],
    string: [[{}, :kelp], [{ strict: true }, Object.new], [{ strict: true }, 4]],
    float: [[{}, '2.345'], [{ round: 1 }, '2.345'], [{}, 'wide']],
    decimal: [[{ round: 2 }, '1.005'], [{}, 'Infinity']],
    boolean: [[{}, 'yes'], [{ values: { truthy: %w[ja], falsy: %w[nein] } }, 'ja'], [{}, 'perhaps']],
    date: [[{}, '2026-03-08'], [{ format: '%d/%m/%Y' }, '08/03/2026'], [{}, 'spring']],
    time: [[{ zone: 'America/Denver' }, '2026-03-08 09:30'], [{}, Date.new(2026, 3, 8)]],
    symbol: [[{}, 'reef'], [{}, 5]],
    binary: [[{}, 'shell']],
    immutable_string: [[{}, 'coral']],
    value: [[{}, [1, 2]]]
  }

  cases.each do |name, examples|
    it "#{name}: coerce_positional matches coerce, results and errors alike" do
      type = FieldStruct.types.lookup(name).new
      examples.each do |options, input|
        keyword = outcome { type.coerce(input, **options, tide_note: 'pass-through') }
        positional = outcome { type.coerce_positional(input, options.merge(tide_note: 'pass-through')) }
        expect(positional).to eq(keyword), "#{name} #{options} #{input.inspect}"
      end
    end
  end

  it 'arrays coerce their elements the same way, element options included' do
    type = FieldStruct::Types::Array.new
    options = { of_type: FieldStruct::Types::Integer, element: { base: 2 } }
    expect(type.coerce_positional(%w[101 11], options)).to eq(type.coerce(%w[101 11], **options))
  end

  it 'is used for built-ins and not for a type that overrides coerce' do
    stretched = Class.new(FieldStruct::Types::Integer) do
      def self.own_option_schema = { depth: option(type: Integer) }

      def coerce(value, depth: 1, **)
        super(value) * depth
      end
    end
    custom = Class.new(FieldStruct::Types::Base) do
      def coerce(value, **) = value
    end
    expect(FieldStruct::Types::Integer.positional_coerce?).to be(true)
    expect(FieldStruct::Types::Binary.positional_coerce?).to be(true)
    expect(stretched.positional_coerce?).to be(false)
    expect(custom.positional_coerce?).to be(false)
  end

  it 'keeps handing every option to an overriding coerce as keywords' do
    stretched = Class.new(FieldStruct::Types::Integer) do
      def self.own_option_schema = { depth: option(type: Integer) }

      def coerce(value, depth: 1, **)
        super(value) * depth
      end
    end
    sounding = Class.new(FieldStruct::Base) { optional :fathoms, stretched, depth: 6 }
    expect(sounding.new(fathoms: '3').fathoms).to eq(18)
  end
end
