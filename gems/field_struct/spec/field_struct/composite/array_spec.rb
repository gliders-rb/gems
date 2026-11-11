# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Array do
  def build(of, **options)
    Class.new(FieldStruct::Base) { field :xs, :array, of: of, **options }
  end

  describe 'FS-B71 declaration' do
    it 'requires of:' do
      expect { build(nil) }.to raise_error(ArgumentError, 'array field requires an `of:` option naming the element type')
      expect { Class.new(FieldStruct::Base) { field :xs, :array } }.to raise_error(ArgumentError, /requires an `of:` option/)
    end

    it 'checks of: shape, then resolves names through the registry' do
      expect { build(5) }.to raise_error(ArgumentError, 'of: on Array expects Symbol or String or Class, got Integer (5)')
      expect { build(:nope) }.to raise_error(KeyError, 'no FieldStruct type registered for :nope')
      expect { build(Object) }.to raise_error(ArgumentError, /not a FieldStruct type/)
    end

    it 'FS-B9: of: on another type names Array and Union' do
      expect { Class.new(FieldStruct::Base) { field :a, :string, of: :string } }.to raise_error(
        ArgumentError, 'of: option does not apply to String fields. It applies to: Array, Union.'
      )
      expect { Class.new(FieldStruct::Base) { field :a, :string, element: {} } }.to raise_error(
        ArgumentError, 'element: option does not apply to String fields. It applies to: Array.'
      )
    end
  end

  describe 'FS-B15 stored options' do
    it 'replaces of: by of_type: (class for scalars) placed first, element: last' do
      options = build(:integer, element: { base: 16 }, avro: 1).metadata[:xs].options
      expect(options.keys).to eq(%i[of_type avro element])
      expect(options[:of_type]).to equal(FieldStruct::Types::Integer)
      expect(options[:element]).to eq(base: 16)
      expect(options[:element]).to be_frozen
    end

    it 'stores a Types::Nested instance for struct elements, by class or by registered name' do
      bed = stub_const('Bed', Class.new(FieldStruct::Base) { optional :habitat, :string })
      of_type = build(bed).metadata[:xs].options[:of_type]
      expect(of_type).to be_a(FieldStruct::Types::Nested)
      expect(of_type.struct_class).to equal(bed)
      registry = FieldStruct.new_registry { register :bd, Bed }
      mod = Module.new.tap { |m| m.define_singleton_method(:field_types) { registry } }
      stub_const('Reg', mod)
      klass = stub_const('Reg::Holder', Class.new(FieldStruct::Base))
      klass.field :xs, :array, of: :bd
      expect(klass.metadata[:xs].options[:of_type].struct_class).to equal(bed)
    end

    it 'accepts a type class directly and drops an empty element:' do
      options = build(FieldStruct::Types::Float, element: {}).metadata[:xs].options
      expect(options).to eq(of_type: FieldStruct::Types::Float)
    end
  end

  describe 'FS-B72 / FS-B73 coercion' do
    let(:klass) { build(:integer) }

    it 'coerces nil, [] and elements into a new Array; nil elements stay nil' do
      source = ['1', nil, 3.9]
      result = klass.new(xs: source).xs
      expect(result).to eq([1, nil, 3])
      expect(result).not_to equal(source)
      expect(klass.new(xs: nil).xs).to be_nil
      expect(klass.new(xs: []).xs).to eq([])
    end

    it 'refuses a non-Array with expected Array, got <class>' do
      instance = klass.new(xs: 'abc')
      expect(instance.errors[:xs]).to eq(['could not be coerced: expected Array, got String'])
      expect(instance.xs).to eq('abc')
    end

    it 'treats nil and [] as missing for required, and only those' do
      req = Class.new(FieldStruct::Base) { required :xs, :array, of: :integer }
      expect(req.new.errors[:xs]).to eq(['is required'])
      expect(req.new(xs: []).errors[:xs]).to eq(['is required'])
      expect(req.new(xs: [0])).to be_valid
      expect(klass.new(xs: [])).to be_valid
    end

    it 'FS-B161: missing? on the type instance' do
      type = described_class.new
      expect([type.missing?([]), type.missing?(nil), type.missing?([nil])]).to eq([true, true, false])
    end

    it 'FS-B164: ruby_type is Array' do
      expect(described_class.new.ruby_type).to eq(Array)
    end

    it 'requires of_type: when coerced directly (array of arrays, FS-B71)' do
      expect { described_class.new.coerce([1]) }.to raise_error(ArgumentError, 'array coerce requires of_type:')
      nested = build(:array)
      instance = nested.new(xs: [[1]])
      expect(instance.errors[:xs].first).to include('element at index 0: array coerce requires of_type:')
    end
  end

  describe 'FS-B74 index messages' do
    let(:klass) { build(:integer) }

    it 'names one bad index' do
      instance = klass.new(xs: [1, 'x', 3])
      expect(instance.errors[:xs]).to eq(
        ['could not be coerced: element at index 1: Integer fields expect a base-10 integer, got a String that is not one']
      )
      expect(instance.xs).to eq([1, 'x', 3])
    end

    it 'names several, showing the first reason' do
      instance = klass.new(xs: [1, 'x', 3, 'y'])
      expect(instance.errors[:xs].first).to start_with('could not be coerced: elements at index 1, 3 (index 1 shown): Integer fields')
    end

    it 'lists at most five indexes, then the count' do
      instance = klass.new(xs: Array.new(20, 'x'))
      expect(instance.errors[:xs].first).to start_with(
        'could not be coerced: elements at index 0, 1, 2, 3, 4 and 15 more (index 0 shown): '
      )
    end

    it 'exposes the phrase builder' do
      expect(described_class.elements_at([2])).to eq('element at index 2')
      expect(described_class.elements_at([0, 2])).to eq('elements at index 0, 2')
      expect(described_class.elements_at((0..6).to_a)).to eq('elements at index 0, 1, 2, 3, 4 and 2 more')
    end

    it 'keeps the first failing element exception class and its cause; never the values' do
      instance = klass.new(xs: ['S3CR3T'])
      expect(instance.errors.to_h.to_s).not_to include('S3CR3T')
      type = described_class.new
      error = begin
        type.coerce([1, :sym], of_type: FieldStruct::Types::Integer)
      rescue TypeError, ArgumentError => e
        e
      end
      expect(error).to be_a(TypeError).or be_a(ArgumentError)
      expect(error.message).to start_with('element at index 1: ')
    end

    it 'FS-B45 / FS-B46: honours the policy for the whole array' do
      replace = Class.new(klass) { coercion_policy :replace }
      expect(replace.new(xs: [1, 'x']).xs).to be_nil
      raising = Class.new(klass) { coercion_policy :raise }
      stub_const('Bag', raising)
      expect do
        raising.new(xs: [1, 'x'])
      end.to raise_error(FieldStruct::CoercionError, /\Acould not coerce Array input for xs: element at index 1: /)
    end
  end

  describe 'FS-B75 element options' do
    it 'passes coercion options to each element' do
      klass = build(:integer, element: { base: 16 })
      expect(klass.new(xs: %w[ff 10]).xs).to eq([255, 16])
      strict = build(:integer, element: { strict: true })
      expect(strict.new(xs: [1.0, 2.5]).errors[:xs].first).to include('element at index 1: ')
    end

    it 'checks validation options per non-nil element after coercion' do
      klass = build(:integer, element: { in: 1..5 })
      expect(klass.new(xs: ['1', nil, 5])).to be_valid
      expect(klass.new(xs: [1, 9, 2]).errors[:xs]).to eq(['element at index 1 is invalid'])
      expect(klass.new(xs: [9, 1, 7]).errors[:xs]).to eq(['elements at index 0, 2 are invalid'])
      many = klass.new(xs: Array.new(8, 9))
      expect(many.errors[:xs]).to eq(['elements at index 0, 1, 2, 3, 4 and 3 more are invalid'])
    end

    it 'checks Regexp format and enum on elements' do
      klass = build(:string, element: { format: /\A\d\z/ })
      expect(klass.new(xs: %w[1 a]).errors[:xs]).to eq(['element at index 1 is invalid'])
      expect(build(:symbol, element: { enum: %i[a b] }).new(xs: %w[a c]).errors[:xs]).to eq(['element at index 1 is invalid'])
    end

    it 'keeps array-level options on the field' do
      klass = build(:integer, default: [1], required: true)
      expect(klass.new.xs).to eq([1])
    end
  end

  describe 'FS-B76 / FS-B162 element: declaration errors' do
    def decl(of, element)
      Class.new(FieldStruct::Base) { field :ids, :array, of: of, element: element }
    end

    it 'prefixes shape errors' do
      expect { decl(:integer, base: '16') }.to raise_error(
        ArgumentError, 'in element: of array field :ids, base: on Integer expects Integer, got String ("16")'
      )
    end

    it 'prefixes the type\'s own value errors' do
      expect do
        decl(:integer,
             base: 40)
      end.to raise_error(ArgumentError, /\Ain element: of array field :ids, base: on Integer expects an Integer from 2 to 36/)
      expect do
        decl(:boolean, values: :nope)
      end.to raise_error(ArgumentError, /\Ain element: of array field :ids, unknown :boolean values preset :nope/)
    end

    it 'refuses keys the element type does not declare, pass-through included' do
      expect { decl(:integer, round: 2) }.to raise_error(
        ArgumentError, 'in element: of array field :ids, round: is not an Integer option. Integer accepts: in, base, strict.'
      )
      expect { decl(:string, avro: { a: 1 }) }.to raise_error(
        ArgumentError, 'in element: of array field :ids, avro: is not a String option. String accepts: format, enum, strict.'
      )
    end

    it 'refuses universal options inside element:' do
      expect { decl(:integer, required: true) }.to raise_error(
        ArgumentError,
        'in element: of array field :ids, required: is a field option, not an element option. Declare it on the field itself.'
      )
    end

    it 'refuses element options for array, union and struct elements' do
      expect do
        decl(:array,
             strict: true)
      end.to raise_error(ArgumentError, 'in element: of array field :ids, element options are not supported for Array elements')
      bed = Class.new(FieldStruct::Base)
      expect { decl(bed, strict: true) }.to raise_error(
        ArgumentError, 'in element: of array field :ids, strict: is not a Nested option. Nested accepts no options.'
      )
    end

    it 'refuses a non-Hash element: with the shape message' do
      expect { decl(:integer, 5) }.to raise_error(ArgumentError, 'element: on Array expects Hash, got Integer (5)')
    end

    it 'FS-B77: shows element options in Metadata and leaves ruby_type alone' do
      klass = decl(:integer, base: 16, strict: true)
      expect(klass.metadata[:ids].options[:element]).to eq(base: 16, strict: true)
      expect(klass.metadata[:ids].type_instance.ruby_type).to eq(Array)
    end
  end

  describe 'FS-B78 arrays of nested structs' do
    let(:bed) do
      stub_const('Bed', Class.new(FieldStruct::Base) do
        required :habitat, :string
        unknown_attributes :raise
      end)
    end

    it 'coerces hashes into instances, passes instances and mixed arrays' do
      klass = build(bed)
      existing = bed.new(habitat: 'Fen')
      result = klass.new(xs: [{ habitat: 'Moor' }, existing]).xs
      expect(result.map(&:class)).to eq([bed, bed])
      expect(result.last).to equal(existing)
    end

    it 'stamps the parent "is invalid" once for any invalid struct' do
      klass = build(bed)
      expect(klass.new(xs: [{ habitat: 'a' }, {}, {}]).errors[:xs]).to eq(['is invalid'])
      expect(klass.new(xs: [{ habitat: 'a' }])).to be_valid
    end

    it 'FS-B31: lets errors from the inner new propagate' do
      klass = build(bed)
      expect { klass.new(xs: [{ habitat: 'a', plot_no: 1 }]) }.to raise_error(FieldStruct::UnknownAttributeError)
    end
  end

  describe 'FS-B40 staleness' do
    it 'does not refresh the parent when an element is mutated in place' do
      bed = stub_const('Bed', Class.new(FieldStruct::Base) { required :habitat, :string })
      klass = build(bed)
      instance = klass.new(xs: [{ habitat: 'a' }])
      instance.xs.first.habitat = nil
      expect(instance).to be_valid
      instance.xs = instance.xs.dup
      expect(instance).to be_invalid
      ints = build(:integer)
      holder = ints.new(xs: [1])
      holder.xs << 'raw'
      expect(holder.xs).to eq([1, 'raw'])
      expect(holder).to be_valid
    end
  end
end
