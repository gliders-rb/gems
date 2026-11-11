# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'construction and assignment' do
  let(:klass) do
    Class.new(described_class) do
      required :name, :string
      optional :height, :integer
    end
  end

  describe 'FS-B18 input' do
    it 'builds with no argument or nil' do
      expect(klass.new.attributes).to eq(name: nil, height: nil)
      expect(klass.new(nil).attributes).to eq(name: nil, height: nil)
    end

    it 'accepts a Hash and anything responding to to_hash' do
      responder = Struct.new(:h) { def to_hash = h }.new({ name: 'Fern' })
      expect(klass.new(name: 'Fern', height: '3').attributes).to eq(name: 'Fern', height: 3)
      expect(klass.new(responder).name).to eq('Fern')
    end

    it 'refuses anything else, naming the class and the input class but not the input' do
      stub_const('Gardener', klass)
      [[], 'secret-value', 5, [[:name, 'x']]].each do |input|
        expect { klass.new(input) }.to raise_error(
          ArgumentError,
          "Gardener.new expects a Hash (or an object responding to #to_hash), got #{input.class}"
        )
      end
    end

    it 'FS-I20: names AnonymousFieldStruct for anonymous classes' do
      expect { klass.new(1) }.to raise_error(
        ArgumentError, 'AnonymousFieldStruct.new expects a Hash (or an object responding to #to_hash), got Integer'
      )
    end

    it 'refuses a non-Hash before any callable default runs' do
      calls = 0
      with_default = Class.new(described_class) { field :a, :integer, default: -> { calls += 1 } }
      expect { with_default.new(1) }.to raise_error(ArgumentError)
      expect(calls).to eq(0)
    end
  end

  describe 'FS-B19 keys' do
    it 'treats Symbol and String keys as the same field, later key winning' do
      expect(klass.new('name' => 'a').name).to eq('a')
      expect(klass.new('name' => 'first', name: 'second').name).to eq('second')
      expect(klass.new(name: 'first', 'name' => 'second').name).to eq('second')
    end

    it 'ignores unknown keys (default policy)' do
      expect(klass.new(name: 'a', nope: 1, 5 => 2).attributes).to eq(name: 'a', height: nil)
    end
  end

  describe 'FS-B21 omitted fields and error key order' do
    it 'sets omitted fields to nil and flags required ones' do
      instance = klass.new
      expect(instance.name).to be_nil
      expect(instance.errors.to_h).to eq(name: ['is required'])
    end

    it 'orders error keys: defaults pass first, then input order' do
      abc = Class.new(described_class) do
        required :a, :string
        required :b, :string
        required :c, :string
      end
      expect(abc.new(c: nil, a: nil).errors.to_h.keys).to eq(%i[b c a])
    end
  end

  describe 'FS-B20 / FS-B22 / FS-B34 defaults' do
    it 'applies literal defaults through the setter and lets given values win' do
      with = Class.new(described_class) { field :n, :integer, default: '5' }
      expect(with.new.n).to eq(5)
      expect(with.new(n: '6').n).to eq(6)
    end

    it 'calls a callable default once per instance and coerces its result' do
      calls = 0
      with = Class.new(described_class) { field :n, :integer, default: -> { "#{calls += 1}0" } }
      expect(with.new.n).to eq(10)
      expect(with.new.n).to eq(20)
      expect(with.new(n: 1).n).to eq(1)
    end

    it 'accepts any callable (Method, lambda) and a callable returning nil' do
      source = Class.new { def self.value = 'x' }
      with = Class.new(described_class) do
        field :a, :string, default: source.method(:value)
        field :b, :string, default: -> {}
      end
      expect(with.new.attributes).to eq(a: 'x', b: nil)
    end

    it 'propagates an error raised by a callable default' do
      with = Class.new(described_class) { field :a, :string, default: -> { raise IOError, 'boom' } }
      expect { with.new }.to raise_error(IOError, 'boom')
    end

    it 'FS-B34: lets defaults satisfy required' do
      with = Class.new(described_class) { required :a, :string, default: 'x' }
      expect(with.new).to be_valid
    end

    it 'FS-B22: an explicit nil with a non-nil default stores nil, and required then fails' do
      with = Class.new(described_class) { required :a, :string, default: 'x' }
      instance = with.new(a: nil)
      expect(instance.a).to be_nil
      expect(instance.errors.to_h).to eq(a: ['is required'])
    end

    it 'runs defaults in declaration order' do
      order = []
      with = Class.new(described_class) do
        field(:a, :string, default: -> { order << :a })
        field(:b, :string, default: -> { order << :b })
      end
      with.new
      expect(order).to eq(%i[a b])
    end
  end

  describe 'FS-B27 assign_attributes' do
    it 'returns self, assigns known keys and leaves the rest alone' do
      instance = klass.new(name: 'a', height: 1)
      expect(instance.assign_attributes('height' => '2', nope: 3)).to equal(instance)
      expect(instance.attributes).to eq(name: 'a', height: 2)
    end

    it 'does not re-run defaults' do
      with = Class.new(described_class) { field :a, :string, default: 'd' }
      instance = with.new(a: 'x')
      instance.assign_attributes({})
      expect(instance.a).to eq('x')
    end

    it 'FS-B18: requires a Hash-like, including nil' do
      stub_const('Gardener', klass)
      instance = klass.new
      expect { instance.assign_attributes(nil) }.to raise_error(
        ArgumentError,
        'Gardener#assign_attributes expects a Hash (or an object responding to #to_hash), got NilClass'
      )
      expect { instance.assign_attributes([1]) }.to raise_error(ArgumentError, /got Array\z/)
    end
  end
end
