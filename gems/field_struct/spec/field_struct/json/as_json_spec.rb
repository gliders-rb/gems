# frozen_string_literal: true

RSpec.describe 'as_json / to_json', :denver do
  def define(&block)
    Class.new(FieldStruct::Base, &block)
  end

  describe 'FS-B104' do
    let(:klass) do
      define do
        required :first, :string
        optional :height, :integer
        optional :nick, :string
        serialize :json, first: 'firstName'
      end
    end

    it 'has Symbol keys in declaration order, every field, mapped names' do
      expect(klass.new(first: 'A', height: 3).as_json).to eq(firstName: 'A', height: 3, nick: nil)
      expect(klass.new(first: 'A').as_json.keys).to eq(%i[firstName height nick])
    end

    it 'ignores its argument' do
      expect(klass.new(first: 'A').as_json(only: [:height])).to eq(klass.new(first: 'A').as_json)
    end

    it 'reads through the reader (an override shows up)' do
      k = define do
        optional :name, :string
        def name = super.to_s.upcase
      end
      expect(k.new(name: 'ab').as_json).to eq(name: 'AB')
    end

    it 'FS-B111: attributes, to_h and deconstruct_keys stay canonical' do
      u = klass.new(first: 'A')
      expect(u.attributes.keys).to eq(%i[first height nick])
      expect(u.to_h.keys).to eq(%i[first height nick])
      expect(u.deconstruct_keys(nil).keys).to eq(%i[first height nick])
    end
  end

  describe 'FS-B105 value conversion' do
    it 'passes nil, booleans, Strings, Integers, Floats; turns Symbols into Strings' do
      k = define do
        optional :a, :value
        optional :b, :symbol
        optional :c, :float
        optional :d, :boolean
      end
      expect(k.new(a: 'x', b: 'sym', c: 1.5, d: true).as_json).to eq(a: 'x', b: 'sym', c: 1.5, d: true)
      expect(k.new(a: :sym).as_json[:a]).to eq('sym')
      expect(k.new(a: 5).as_json[:a]).to eq(5)
    end

    it 'writes BigDecimal as a plain decimal string' do
      k = define { optional :n, :decimal }
      expect(k.new(n: BigDecimal('1234567890123.4567')).as_json[:n]).to eq('1234567890123.4567')
      expect(k.new(n: '1e3').as_json[:n]).to eq('1000.0')
      expect(k.new(n: '1e3').to_json).to eq('{"n":"1000.0"}')
    end

    it 'renders temporals by the field format' do
      k = define do
        optional :d, :date, format: :us
        optional :t, :time, format: '%H:%M'
        optional :s, :datetime, format: :iso8601
        optional :p, :time
        optional :q, :date
      end
      json = k.new(d: '07/03/2026', t: '10:30', s: '2026-07-03T10:30:00+00:00', p: Time.utc(2026, 7, 3, 1), q: '2026-07-03').as_json
      expect(json).to eq(d: '07/03/2026', t: '10:30', s: '2026-07-03T10:30:00Z', p: '2026-07-03T01:00:00Z', q: '2026-07-03')
    end

    it 'uses the object iso8601 without a format, keeping a fraction when there is one' do
      k = define do
        optional :a, :datetime
        optional :b, :time
      end
      u = k.new(a: DateTime.new(2026, 7, 3, 10, 30, 0, '+00:00'), b: Time.new(2026, 7, 3, 10, 30, 0.25r, '-06:00'))
      expect(u.as_json).to eq(a: '2026-07-03T10:30:00+00:00', b: '2026-07-03T10:30:00.25-06:00')
    end

    it 'uses the element format for array fields' do
      k = define { optional :ds, :array, of: :date, element: { format: :us } }
      expect(k.new(ds: ['07/03/2026', '01/02/2025']).as_json).to eq(ds: %w[07/03/2026 01/02/2025])
      expect(define { optional :ds, :array, of: :date }.new(ds: ['2026-07-03']).as_json).to eq(ds: ['2026-07-03'])
    end

    it 'walks arrays and hashes, and asks nested structs for their own as_json' do
      inner = define do
        required :id, :integer
        optional :at, :date, format: :eu
        serialize :json, id: 'ID'
      end
      k = define do
        optional :inner, inner
        optional :list, :array, of: inner
        optional :bag, :value
      end
      u = k.new(inner: { id: 1, at: '03/07/2026' }, list: [{ id: 2 }],
                bag: { 'k' => [:s, { 'z' => BigDecimal('2.5') }], 'd' => Date.new(2026, 1, 2) })
      expect(u.as_json).to eq(
        inner: { ID: 1, at: '03/07/2026' }, list: [{ ID: 2, at: nil }], bag: { 'k' => ['s', { 'z' => '2.5' }], 'd' => '2026-01-02' }
      )
    end

    it 'FS-B105 last arm: an object that answers as_json is asked, any other is passed through' do
      thing = Class.new { def as_json(*) = { 'custom' => 1 } }.new
      plain = Object.new
      k = define { optional :v, :value }
      expect(k.new(v: thing).as_json[:v]).to eq('custom' => 1)
      expect(k.new(v: plain).as_json[:v]).to equal(plain) unless Object.method_defined?(:as_json)
    end

    it 'FS-I15: sensitive fields are not masked' do
      expect(define { optional :pw, :string, sensitive: true }.new(pw: 'secret').as_json).to eq(pw: 'secret')
    end
  end

  describe 'FS-B106 to_json' do
    it 'is Oj in compat mode, ignores its argument, emits every field' do
      k = define do
        required :a, :integer
        optional :b, :string
        serialize :json, a: 'A'
      end
      expect(k.new(a: 1).to_json).to eq('{"A":1,"b":null}')
      expect(k.new(a: 1).to_json(only: [:a])).to eq('{"A":1,"b":null}')
    end
  end
end
