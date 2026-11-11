# frozen_string_literal: true

RSpec.describe 'from_json', :denver do
  def define(&block)
    Class.new(FieldStruct::Base, &block)
  end

  let(:gardener) do
    define do
      required :name, :string
      optional :height, :integer
    end
  end

  describe 'FS-B107 parsing' do
    it 'builds an instance through new' do
      u = gardener.from_json('{"name":"Fern","height":3}')
      expect(u).to be_a(gardener)
      expect([u.name, u.height]).to eq(['Fern', 3])
      expect(u).to be_valid
    end

    it 'keeps bad data usable, like new' do
      u = gardener.from_json('{"height":"abc"}')
      expect(u.errors.to_h.keys).to eq(%i[name height])
    end

    it 'follows unknown_attributes and coercion_policy of the class' do
      strict = define do
        unknown_attributes :raise
        coercion_policy :raise
        optional :n, :integer
      end
      expect { strict.from_json('{"zz":1}') }.to raise_error(FieldStruct::UnknownAttributeError)
      expect { strict.from_json('{"n":"x"}') }.to raise_error(FieldStruct::CoercionError)
      expect(gardener.from_json('{"name":"a","zz":1}').name).to eq('a')
    end

    it 'refuses a non-object root, naming the parsed class' do
      expect { gardener.from_json('[1]') }.to raise_error(ArgumentError, 'from_json expects a JSON object root, got Array')
      expect { gardener.from_json('3') }.to raise_error(ArgumentError, 'from_json expects a JSON object root, got Integer')
      expect { gardener.from_json('"x"') }.to raise_error(ArgumentError, 'from_json expects a JSON object root, got String')
      expect { gardener.from_json('null') }.to raise_error(ArgumentError, 'from_json expects a JSON object root, got NilClass')
      expect { gardener.from_json(nil) }.to raise_error(ArgumentError, 'from_json expects a JSON object root, got NilClass')
    end

    it 'raises EncodingError with a sanitized message and no cause for malformed JSON' do
      secret = 'TOP-SECRET-VALUE'
      ['', '   ', '{', '{"a" 1}', "{\"#{secret}\" 1}", "{\"a\":#{secret}}", '{"a":1,}'].each do |input|
        expect { gardener.from_json(input) }.to raise_error(EncodingError) { |error|
          expect(error.class).to equal(EncodingError)
          expect(error.message).to match(/\Afrom_json could not parse its input as JSON \(.+ at line \d+, column \d+\)\z/)
          expect(error.message).not_to include(secret)
          expect(error.message).not_to include('[parse.c')
          expect(error.cause).to be_nil
        }
      end
    end

    it 'describes the problem and position' do
      expect do
        gardener.from_json('{"a" 1}')
      end.to raise_error(EncodingError,
                         'from_json could not parse its input as JSON (expected colon at line 1, column 6)')
    end
  end

  describe 'FS-B108 BigDecimal parsing' do
    it 'sends fractions and exponents as BigDecimal and whole numbers as Integers' do
      k = define do
        optional :d, :decimal
        optional :f, :float
        optional :i, :integer
        optional :v, :value
      end
      u = k.from_json('{"d":1234567890123.4567,"f":2.5,"i":3.7,"v":{"x":2.25,"y":[7,1.5]}}')
      expect(u.d).to eq(BigDecimal('1234567890123.4567'))
      expect(u.f).to be_a(Float)
      expect(u.i).to eq(3)
      expect(u.v['x']).to be_a(BigDecimal)
      expect(u.v['y'].first).to eq(7)
      expect(u.v['y'].first).to be_a(Integer)
      expect(u.to_json).to include('"v":{"x":"2.25","y":[7,"1.5"]}')
    end

    it 'treats 1e400 as finite for decimal and integer, and refuses it for float' do
      k = define do
        optional :d, :decimal
        optional :i, :integer
        optional :f, :float
      end
      u = k.from_json('{"d":1e400,"i":1e400,"f":1e400}')
      expect(u.d).to eq(BigDecimal('1e400'))
      expect(u.i).to eq(10**400)
      expect(u.errors[:f].first).to start_with('could not be coerced')
    end

    it 'FS-B62: refuses a huge exponent fast' do
      k = define { optional :i, :integer }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      u = k.from_json('{"i":1e10000000}')
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
      expect(u.errors[:i].first).to include('4300')
    end
  end

  describe 'FS-B109 reverse mapping' do
    let(:bed) do
      define do
        optional :habitat, :string
        optional :plot_no, :string
        serialize :json, plot_no: 'postalCode'
      end
    end
    let(:company) { define { optional :label, :string } }

    let(:holder) do
      bd = bed
      comp = company
      define do
        required :full_name, :string
        optional :border, bd
        optional :others, :array, of: bd
        optional :owner, :union, of: [bd, :integer]
        optional :tags, :array, of: :string
        optional :boss, :union, of: [comp, :integer]
        serialize :json, full_name: 'fullName', others: 'otherAddresses'
      end
    end

    it 'maps external names, also accepts canonical ones' do
      expect(holder.from_json('{"fullName":"A"}').full_name).to eq('A')
      expect(holder.from_json('{"full_name":"A"}').full_name).to eq('A')
    end

    it 'treats an unmapped external key that is not a field as unknown' do
      expect(holder.from_json('{"fullName":"A","bogus":1}').full_name).to eq('A')
      strict = Class.new(holder) { unknown_attributes :raise }
      expect { strict.from_json('{"fullName":"A","bogus":1}') }.to raise_error(FieldStruct::UnknownAttributeError, /:bogus/)
    end

    it 'recurses into nested structs with the nested class own mapping' do
      u = holder.from_json('{"fullName":"A","border":{"habitat":"X","postalCode":"123"}}')
      expect([u.border.habitat, u.border.plot_no]).to eq(%w[X 123])
    end

    it 'recurses into each Hash element of an array of structs' do
      u = holder.from_json('{"otherAddresses":[{"postalCode":"1"},{"postalCode":"2","habitat":"c"}]}')
      expect(u.others.map(&:plot_no)).to eq(%w[1 2])
    end

    it 'unions: a struct member reverse-maps through its own mapping and constructs' do
      u = holder.from_json('{"owner":{"postalCode":"9"}}')
      expect(u.owner).to be_a(bed)
      expect(u.owner.plot_no).to eq('9')
      expect(holder.from_json('{"owner":5}').owner).to eq(5)
    end

    it 'unions: a non-struct member that accepts the raw Hash wins and leaves it untouched' do
      bd = bed
      k = define { optional :u, :union, of: [:value, bd] }
      expect(k.from_json('{"u":{"postalCode":"9"}}').u).to eq('postalCode' => '9')
    end

    it 'unions: when no member accepts, the raw Hash goes to the field policy' do
      strict_member = define do
        unknown_attributes :raise
        optional :a, :string
      end
      k = define { optional :u, :union, of: [strict_member, :integer] }
      u = k.from_json('{"u":{"zz":1}}')
      expect(u.errors[:u].first).to start_with('could not be coerced')
    end

    it 'unions: the first accepting struct member wins, each through its own mapping' do
      one = define do
        unknown_attributes :raise
        optional :a, :string
        serialize :json, a: 'x'
      end
      two = define do
        unknown_attributes :raise
        optional :b, :string
        serialize :json, b: 'y'
      end
      k = define { optional :u, :union, of: [one, two] }
      expect(k.from_json('{"u":{"y":"v"}}').u).to be_a(two)
      expect(k.from_json('{"u":{"x":"v"}}').u.a).to eq('v')
    end

    it 'leaves Hashes inside a :value array alone' do
      arr = define { optional :items, :array, of: :value }
      expect(arr.from_json('{"items":[{"a":1}]}').items).to eq([{ 'a' => 1 }])
    end
  end

  describe 'FS-B110 round trip' do
    let(:line) do
      define do
        required :sku, :string
        optional :yield_kg, :decimal
        serialize :json, sku: 'SKU'
      end
    end
    let(:circle) do
      define do
        unknown_attributes :raise
        optional :radius, :float
        serialize :json, radius: 'r'
      end
    end
    let(:square) do
      define do
        unknown_attributes :raise
        optional :side, :integer
        serialize :json, side: 's'
      end
    end

    it 'restores equal instances for every type except :value' do
      l = line
      c = circle
      s = square
      k = define do
        required :name, :string
        optional :sym, :symbol
        optional :n, :integer
        optional :f, :float
        optional :yield_kg, :decimal
        optional :flag, :boolean
        optional :on, :date, format: :us
        optional :at, :time
        optional :at2, :time, format: :iso8601
        optional :dt, :datetime, format: :db
        optional :dt2, :datetime
        optional :raw, :binary
        optional :uid, :uuid
        optional :lines, :array, of: l
        optional :dates, :array, of: :date, element: { format: :eu }
        optional :shape, :union, of: [c, s]
        optional :shape2, :union, of: [s, c]
        optional :nested, l
        optional :either, :union, of: %i[integer string]
        serialize :json, name: 'NAME', lines: 'LINES', on: 'ON'
      end
      u = k.new(name: 'x', sym: :abc, n: 5, f: 1.5, yield_kg: '12.345', flag: false, on: '07/03/2026',
                at: Time.new(2026, 7, 3, 10, 30, 0.123456r, '-06:00'), at2: '2026-07-03T10:30:00.5+02:00',
                dt: '2026-07-03 10:30:00', dt2: DateTime.new(2026, 7, 3, 10, 30, 0, '+05:30'),
                raw: 'abc', uid: '123e4567-e89b-42d3-a456-426614174000',
                lines: [{ sku: 'a', yield_kg: '1.5' }, { sku: 'b' }], dates: ['03/07/2026'],
                shape: { radius: 2.5 }, shape2: { 'side' => 3 }, nested: { sku: 'n', yield_kg: '9' }, either: 'str')
      expect(u).to be_valid
      back = k.from_json(u.to_json)
      expect(back).to eq(u)
      expect(back).to be_valid
      expect(back.lines.first).to be_a(l)
      expect(back.shape).to be_a(c)
    end

    it 'works without any mapping and for subclasses' do
      k = define do
        required :a, :string
        optional :b, :integer
      end
      sub = Class.new(k) { optional :c, :float }
      u = sub.new(a: 'x', b: 2, c: 0.5)
      expect(sub.from_json(u.to_json)).to eq(u)
    end

    it 'FS-I13: a :value field loses type info (a Symbol comes back a String)' do
      k = define { optional :v, :value }
      expect(k.from_json(k.new(v: { s: :sym }).to_json).v).to eq('s' => 'sym')
    end
  end
end
