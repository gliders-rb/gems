# frozen_string_literal: true

RSpec.describe FieldStruct::JSONSchema, 'overrides and custom types' do
  def custom_type(schema: :none, ruby: Rational, &body)
    Class.new(FieldStruct::Types::Base) do
      define_method(:coerce) { |value, **| value }
      define_method(:ruby_type) { ruby }
      define_method(:json_schema) { schema } unless schema == :none
      class_eval(&body) if body
    end
  end

  describe 'JS-B12: custom types' do
    it 'names the ruby_type classes in x-ruby-type and adds nothing for optional fields' do
      rational = custom_type
      multi = custom_type(ruby: [Integer, Symbol])
      klass = struct do
        required :r, rational
        optional :o, rational
        required :m, multi
      end
      expect(property(klass, :r)).to eq('x-ruby-type' => 'Rational')
      expect(property(klass, :o)).to eq('x-ruby-type' => 'Rational')
      expect(property(klass, :m)).to eq('x-ruby-type' => 'Integer | Symbol')
    end

    it 'uses the type hook when it returns a Hash, true or false' do
      int = custom_type(schema: { 'type' => 'integer' })
      yes = custom_type(schema: true)
      no = custom_type(schema: false)
      klass = struct do
        required :h, int
        required :t, yes
        required :f, no
        optional :n, int
      end
      expect(property(klass, :h)).to eq('type' => 'integer')
      expect(property(klass, :t)).to eq({})
      expect(property(klass, :f)).to eq('not' => {})
      expect(property(klass, :n)).to eq('type' => %w[integer null])
    end

    it 'falls back to x-ruby-type when the hook returns nil' do
      declining = custom_type(schema: nil)
      klass = struct { required :r, declining }
      expect(property(klass, :r)).to eq('x-ruby-type' => 'Rational')
    end

    it 'applies the hook to elements of arrays' do
      int = custom_type(schema: { 'type' => 'integer' })
      klass = struct { required :tags, :array, of: int }
      expect(property(klass, :tags)['items']).to eq('type' => %w[integer null])
    end

    it 'makes a hooked schema nullable like any other (no blank-string alternative off the String family)' do
      shouty = custom_type(schema: { 'type' => 'string', 'pattern' => '^[A-Z]+$' })
      klass = struct { optional :s, shouty }
      expect(property(klass, :s)).to eq('type' => %w[string null], 'pattern' => '^[A-Z]+$')
    end

    it 'gives a String subtype with a hook the blank-string alternative when optional' do
      shouty = Class.new(FieldStruct::Types::String) { define_method(:json_schema) { { 'type' => 'string', 'pattern' => '^[A-Z]+$' } } }
      klass = struct { optional :s, shouty }
      expect(property(klass, :s)['anyOf'].last).to eq(described_class::BLANK_STRING)
    end
  end

  describe 'JS-B13: field-level json_schema:' do
    it 'accepts a Hash, true and false' do
      klass = struct do
        required :h, :string, json_schema: { 'type' => 'integer', 'minimum' => 3 }
        required :t, :string, json_schema: true
        required :f, :string, json_schema: false
        optional :n, :string, json_schema: { 'type' => 'integer' }
        optional :legacy, :value, json_schema: false
      end
      expect(property(klass, :h)).to eq('type' => 'integer', 'minimum' => 3)
      expect(property(klass, :t)).to eq({})
      expect(property(klass, :f)).to eq('not' => {})
      expect(property(klass, :n)).to eq('type' => %w[integer null])
      expect(property(klass, :legacy)).to eq('anyOf' => [{ 'not' => {} }, { 'type' => 'null' }])
    end

    it 'beats the type hook, which is then not asked' do
      asked = false
      type = custom_type(schema: { 'type' => 'integer' }) do
        define_method(:json_schema) do
          asked = true
          {}
        end
      end
      klass = struct { required :x, type, json_schema: { 'type' => 'boolean' } }
      expect(property(klass, :x)).to eq('type' => 'boolean')
      expect(asked).to be(false)
    end

    it 'never builds the element of an array that has an override' do
      boom = custom_type { define_method(:json_schema) { raise 'asked' } }
      klass = struct { required :xs, :array, of: boom, json_schema: { 'type' => 'array' } }
      expect(property(klass, :xs)).to eq('type' => 'array')
    end

    it 'keeps annotations beside an override' do
      klass = struct { optional :x, :string, description: 'd', default: 'a', json_schema: { 'type' => 'string' } }
      expect(property(klass, :x)).to eq('description' => 'd', 'default' => 'a', 'type' => %w[string null])
    end

    it 'does not change the Hash it was given' do
      given = { 'type' => 'integer' }.freeze
      klass = struct { optional :x, :integer, json_schema: given }
      expect(property(klass, :x)).to eq('type' => %w[integer null])
      expect(given).to eq('type' => 'integer')
    end
  end

  describe 'JS-B13: errors' do
    it 'names the field for a bad override' do
      stub_const('BadOverride', struct { required :t, :string, json_schema: [1] })
      expect { described_class.generate(BadOverride) }.to raise_error(
        ArgumentError,
        'FieldStruct::JSONSchema.generate: the json_schema: option of BadOverride#t must be a Hash or a boolean, got [1]'
      )
    end

    it 'names the type and field for a bad hook result' do
      stub_const('Shouty', custom_type(schema: [1]))
      stub_const('UsesShouty', struct { required :s, Shouty })
      expect { described_class.generate(UsesShouty) }.to raise_error(
        ArgumentError, 'FieldStruct::JSONSchema.generate: Shouty#json_schema (for UsesShouty#s) must be a Hash or a boolean, got [1]'
      )
    end

    it 'wraps a raising hook and keeps the original as cause' do
      stub_const('Exploding', custom_type { define_method(:json_schema) { {}.fetch('missing') } })
      stub_const('UsesExploding', struct { required :tags, :array, of: Exploding })
      expect { described_class.generate(UsesExploding) }.to raise_error(ArgumentError) { |error|
        expect(error.message).to eq(
          'FieldStruct::JSONSchema.generate: Exploding#json_schema raised KeyError (for UsesExploding#tags): key not found: "missing"'
        )
        expect(error.cause).to be_a(KeyError)
      }
    end

    it 'chains the field path through anonymous structs' do
      stub_const('Shouty', custom_type(schema: [1]))
      inner = struct { required :x, Shouty }
      stub_const('Holder', struct { required :inner, inner })
      expect { described_class.generate(Holder) }.to raise_error(ArgumentError, /\(for Holder#inner\.x\)/)
    end
  end

  describe 'Methods' do
    it 'JS-B13/Methods: adds to_json_schema to classes that include it, and only to those' do
      with = struct do
        include FieldStruct::JSONSchema::Methods

        required :a, :string
      end
      expect(with.to_json_schema).to eq(described_class.generate(with))
      expect(with.to_json_schema(serialization: 'json')).to eq(described_class.generate(with))
      expect(struct).not_to respond_to(:to_json_schema)
    end
  end
end
