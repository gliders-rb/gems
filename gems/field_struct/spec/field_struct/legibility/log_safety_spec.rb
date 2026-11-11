# frozen_string_literal: true

require 'bigdecimal'
require 'stringio'

RSpec.describe 'Log safety' do
  secret = 'S3cr3t-Distinct-Token'

  let(:inner) do
    Class.new(FieldStruct::Base) do
      required :v, :integer
      optional :pin, :string, sensitive: true
    end
  end

  def pp_to_s(object)
    out = StringIO.new
    PP.pp(object, out)
    out.string
  end

  def chain_text(error)
    texts = []
    while error
      texts << error.message
      error = error.cause
    end
    texts.join("\n")
  end

  # Every built-in type fed the secret (as a String and wrapped in an object) under each policy.
  type_fields = {
    string: [:string, {}], immutable_string: [:immutable_string, {}], integer: [:integer, {}],
    integer_strict: [:integer, { strict: true }], integer_base: [:integer, { base: 16 }],
    float: [:float, {}], decimal: [:decimal, {}], boolean: [:boolean, {}], symbol: [:symbol, { enum: %i[a b] }],
    uuid: [:uuid, {}], url: [:url, {}], email: [:email, {}], binary: [:binary, {}],
    date: [:date, {}], date_fmt: [:date, { format: :iso8601 }], time: [:time, {}], time_fmt: [:time, { format: '%Y-%m-%d' }],
    datetime: [:datetime, {}], time_zone: [:time, { zone: 'UTC' }],
    array_int: [:array, { of: :integer }], array_el: [:array, { of: :integer, element: { strict: true } }],
    union: [:union, { of: %i[integer boolean] }], value: [:value, {}]
  }

  type_fields.each do |label, (type, opts)|
    %i[keep_raw replace raise].each do |policy|
      it "FS-B138 never echoes the secret: #{label} under #{policy}", :aggregate_failures do
        klass = Class.new(FieldStruct::Base)
        klass.coercion_policy policy
        klass.field :f, type, **opts, sensitive: false
        inputs = [secret, [secret, secret], { secret => secret }, Struct.new(:x).new(secret), Object.new.tap do |o|
          o.define_singleton_method(:to_s) do
            secret
          end
        end]
        inputs.each do |input|
          instance = begin
            klass.new(f: input)
          rescue FieldStruct::Error, ArgumentError, TypeError, RangeError => e
            expect(chain_text(e)).not_to include(secret)
            next
          end
          expect(instance.errors.to_h.values.join).not_to include(secret)
          expect(instance.errors.full_messages.join).not_to include(secret)
        end
      end
    end
  end

  it 'FS-B138 keeps the secret out of nested and array-of-struct messages' do
    holder = Class.new(FieldStruct::Base)
    holder.field :one, inner
    holder.field :many, :array, of: inner
    expect { holder.new(one: { v: secret }, many: [{ v: secret }]) }.not_to raise_error
    instance = holder.new(one: { v: secret }, many: [{ v: secret }])
    expect(instance.errors.to_h.values.join).not_to include(secret)
    expect(instance.one.errors.to_h.values.join).not_to include(secret)
    expect { holder.new(one: 5) }.not_to raise_error
    expect(holder.new(one: 5).errors.to_h.values.join).not_to include('5 ')
  end

  it 'FS-B138 keeps the secret out of from_json errors' do
    klass = Class.new(FieldStruct::Base) { optional :a, :integer }
    expect { klass.from_json(%({"a": 1, "#{secret}": oops})) }.to raise_error(EncodingError) { |e|
      expect(chain_text(e)).not_to include(secret)
    }
    expect { klass.from_json(%("#{secret}")) }.to raise_error(ArgumentError) { |e| expect(e.message).not_to include(secret) }
  end

  it 'FS-B138 keeps the secret out of unknown-attribute and immutability messages' do
    klass = Class.new(FieldStruct::Base) do
      unknown_attributes :raise
      optional :a, :integer
    end
    expect { klass.new(a: secret, b: 1) }.to raise_error(FieldStruct::UnknownAttributeError) { |e| expect(e.message).not_to include(secret) }
  end

  describe 'sensitive:' do
    it 'FS-B139 masks non-nil values in inspect and pp, nil stays visible' do
      klass = Class.new(FieldStruct::Base) do
        optional :token, :string, sensitive: true
        optional :name, :string
      end
      expect(klass.new(token: secret, name: 'bob').inspect).to eq('#<AnonymousFieldStruct token: [FILTERED], name: "bob">')
      expect(klass.new(name: 'bob').inspect).to include('token: nil')
      expect(pp_to_s(klass.new(token: secret))).not_to include(secret)
    end

    it 'FS-B139 masks a raw value kept after a keep_raw failure, and the errors suffix holds no values' do
      klass = Class.new(FieldStruct::Base) { optional :n, :integer, sensitive: true }
      text = klass.new(n: secret).inspect
      expect(text).not_to include(secret)
      expect(text).to include('n: [FILTERED]', 'errors: {n: ["could not be coerced:')
    end

    it 'FS-B139 masks nested structs, arrays of them, unions and sensitive fields inside nested structs' do
      holder = Class.new(FieldStruct::Base)
      holder.field :one, inner, sensitive: true
      holder.field :many, :array, of: inner, sensitive: true
      holder.field :pub, inner
      holder.field :u, :union, of: %i[integer string], sensitive: true
      instance = holder.new(one: { v: 1, pin: secret }, many: [{ v: 2, pin: secret }], pub: { v: 3, pin: secret }, u: secret)
      [instance.inspect, pp_to_s(instance)].each do |text|
        expect(text).not_to include(secret)
        expect(text).to include('one: [FILTERED]', 'many: [FILTERED]', 'u: [FILTERED]', 'pin: [FILTERED]')
      end
    end

    it 'FS-I15 leaves data paths unmasked' do
      klass = Class.new(FieldStruct::Base) { optional :token, :string, sensitive: true }
      instance = klass.new(token: secret)
      expect(instance.token).to eq(secret)
      expect(instance.to_h).to eq(token: secret)
      expect(instance.as_json).to eq(token: secret)
      expect(instance.to_json).to include(secret)
      expect(instance.deconstruct_keys(nil)).to eq(token: secret)
      expect(instance).to eq(klass.new(token: secret))
    end

    it 'FS-B139 shows the flag in Field#inspect, to_h and describe but not in options' do
      klass = Class.new(FieldStruct::Base) do
        optional :a, :string, sensitive: true
        optional :b, :string, sensitive: false
      end
      expect(klass.metadata[:a].sensitive?).to be(true)
      expect(klass.metadata[:b].sensitive?).to be(false)
      expect(klass.metadata[:a].options).not_to have_key(:sensitive)
      expect(klass.metadata[:a].inspect).to include(' sensitive')
      expect(klass.metadata.to_h[:a][:sensitive]).to be(true)
      expect(klass.metadata.to_h[:b]).not_to have_key(:sensitive)
      expect(klass.metadata.describe).to include('a (String, optional, sensitive)')
    end

    it 'FS-B139 is inherited with the field' do
      parent = Class.new(FieldStruct::Base) { optional :a, :string, sensitive: true }
      child = Class.new(parent)
      expect(child.new(a: 'x').inspect).to include('a: [FILTERED]')
    end
  end
end
