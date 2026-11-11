# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Union do
  def build(of, **options)
    Class.new(FieldStruct::Base) { field :v, :union, of: of, **options }
  end

  describe 'declaration (FS-B82 / 4.11)' do
    it 'requires of:' do
      expect { Class.new(FieldStruct::Base) { field :v, :union } }.to raise_error(
        ArgumentError, 'union field requires an `of: [...]` option naming the member types'
      )
      expect { build(nil) }.to raise_error(ArgumentError, /requires an `of: \[\.\.\.\]` option/)
    end

    it 'checks the shape, the count and unknown names' do
      expect { build('x') }.to raise_error(ArgumentError, 'of: on Union expects Array, got String ("x")')
      expect { build([]) }.to raise_error(ArgumentError, 'union `of:` must have at least two members')
      expect { build([:string]) }.to raise_error(ArgumentError, 'union `of:` must have at least two members')
      expect { build(%i[string nope]) }.to raise_error(KeyError, 'no FieldStruct type registered for :nope')
    end

    it 'R7: refuses :array members in every spelling' do
      message = 'union `of:` cannot include :array (an array member would have no element type); give the array its own field or use :value'
      expect { build(%i[string array]) }.to raise_error(ArgumentError, message)
      expect { build([:string, FieldStruct::Types::Array]) }.to raise_error(ArgumentError, message)
      sub = Class.new(FieldStruct::Types::Array)
      expect { build([:string, sub]) }.to raise_error(ArgumentError, message)
    end

    it 'removes of: from options and keeps members on the type instance' do
      klass = build(%i[integer string], doc: 1)
      expect(klass.metadata[:v].options).to eq(doc: 1)
      members = klass.metadata[:v].type_instance.member_types
      expect(members.map(&:class)).to eq([FieldStruct::Types::Integer, FieldStruct::Types::String])
      expect(klass.metadata[:v].type).to equal(described_class)
    end

    it 'FS-B158: gives struct members as Nested instances' do
      a = stub_const('A', Class.new(FieldStruct::Base))
      klass = build([a, :string])
      first = klass.metadata[:v].type_instance.member_types.first
      expect(first).to be_a(FieldStruct::Types::Nested)
      expect(first.struct_class).to equal(a)
    end

    it 'FS-B9: wrong-type options on a union' do
      expect { build(%i[integer string], round: 1) }.to raise_error(ArgumentError, /round: option does not apply to Union fields/)
    end
  end

  describe 'FS-B83 coercion' do
    it 'tries members in declared order' do
      expect(build(%i[integer string]).new(v: '42').v).to eq(42)
      expect(build(%i[string integer]).new(v: '42').v).to eq('42')
      expect(build(%i[integer boolean]).new(v: 'true').v).to be(true)
      expect(build(%i[integer string]).new(v: nil).v).to be_nil
    end

    it 'refuses with a class-only message when every member refuses' do
      instance = build(%i[integer boolean]).new(v: 'zzz')
      expect(instance.errors[:v]).to eq(['could not be coerced: no union member (Integer | Boolean) could coerce String input'])
      expect(instance.v).to eq('zzz')
    end

    it 'refuses non-finite numbers before trying any member' do
      klass = build(%i[string integer])
      message = 'could not be coerced: Union fields expect a finite number, got a non-finite Float'
      expect(klass.new(v: Float::NAN).errors[:v]).to eq([message])
      expect(klass.new(v: BigDecimal('Infinity')).errors[:v].first).to include('non-finite BigDecimal')
    end

    it 'does not hand field options to members' do
      expect(build(%i[integer string], doc: 'x').new(v: '7').v).to eq(7)
    end

    it 'lets a struct member that rejects the value fall through to the next' do
      a = stub_const('A', Class.new(FieldStruct::Base) do
        required :a, :string
        unknown_attributes :raise
      end)
      b = stub_const('B', Class.new(FieldStruct::Base) { required :b, :string })
      klass = build([a, b])
      expect(klass.new(v: { b: 'x' }).v).to be_a(b)
      expect(klass.new(v: { a: 'x' }).v).to be_a(a)
      expect(klass.new(v: 5).errors[:v]).to eq(['could not be coerced: no union member (Nested | Nested) could coerce Integer input'])
    end

    it 'propagates exceptions that are not coercion failures' do
      boom = Class.new(FieldStruct::Types::Base) do
        def coerce(_value, **) = raise(NoMethodError, 'bug')
        def ruby_type = Object
      end
      klass = Class.new(FieldStruct::Base) { field :v, :union, of: [boom, :string] }
      expect { klass.new(v: 'x') }.to raise_error(NoMethodError)
    end
  end

  describe 'FS-B84 / FS-B161 / FS-B164' do
    it 'flattens and de-duplicates ruby_type; booleans contribute both' do
      a = stub_const('A', Class.new(FieldStruct::Base))
      type = build([:integer, :boolean, :float, a, :decimal, :big_decimal]).metadata[:v].type_instance
      expect(type.ruby_type).to eq([Integer, TrueClass, FalseClass, Float, a, BigDecimal])
    end

    it 'is missing only for nil' do
      type = build(%i[string integer]).metadata[:v].type_instance
      expect([type.missing?(nil), type.missing?(''), type.missing?(0)]).to eq([true, false, false])
    end

    it 'exposes RESCUABLE' do
      expect(described_class::RESCUABLE).to eq([ArgumentError, TypeError, RangeError, FieldStruct::Error])
    end

    it 'is required for a required union field only when nil' do
      klass = Class.new(FieldStruct::Base) { required :v, :union, of: %i[string integer] }
      expect(klass.new.errors[:v]).to eq(['is required'])
      expect(klass.new(v: 1)).to be_valid
    end
  end
end
