# frozen_string_literal: true

RSpec.describe 'FieldStruct::Protobuf.file_descriptor (scalars)' do
  def descriptor(klass, **)
    FieldStruct::Protobuf.file_descriptor(klass, **)
  end

  def fields_of(klass, **)
    descriptor(klass, **).message_type.first.field.to_h { |f| [f.name, f] }
  end

  describe 'numbers (PB-B1, PB-B2)' do
    it 'PB-B1: refuses unnumbered fields, naming the property keys in declaration order' do
      klass = define_struct('Unnumbered') do
        required :a, :string, proto: { number: 1 }
        required :b, :string
        optional :c, :string, proto: { number: 3 }
        optional :d, :string
      end
      expect { descriptor(klass) }.to raise_error(
        ArgumentError, 'Unnumbered: give every field a protobuf field number, e.g. `proto: {number: 1}`; missing on b, d'
      )
    end

    it 'PB-B1: treats an empty proto hash as unnumbered' do
      klass = define_struct('Unnumbered') { required :a, :string, proto: {} }
      expect { descriptor(klass) }.to raise_error(ArgumentError, /missing on a\z/)
    end

    it 'PB-B1: refuses a number used twice' do
      klass = define_struct('Twice') do
        required :a, :string, proto: { number: 1 }
        required :b, :string, proto: { number: 1 }
        required :c, :string, proto: { number: 2 }
        required :d, :string, proto: { number: 2 }
      end
      expect { descriptor(klass) }.to raise_error(ArgumentError, 'Twice: field numbers 1, 2 are used twice')
    end

    it 'PB-B1: refuses numbers outside 1..536_870_911, in the reserved range, or not Integers' do
      [0, -1, 536_870_912, 19_000, 19_500, 19_999, '1', 1.0].each do |bad|
        klass = define_struct('Reserved') { required :a, :string, proto: { number: bad } }
        expect { descriptor(klass) }.to raise_error(ArgumentError, "Reserved#a: #{bad.inspect} isn't a usable protobuf field number")
      end
    end

    it 'PB-B1: accepts the edges 1, 18_999, 20_000 and 536_870_911' do
      klass = define_struct('Edges') do
        required :a, :string, proto: { number: 1 }
        required :b, :string, proto: { number: 18_999 }
        required :c, :string, proto: { number: 20_000 }
        required :d, :string, proto: { number: 536_870_911 }
      end
      expect(fields_of(klass).values.map(&:number)).to eq([1, 18_999, 20_000, 536_870_911])
    end

    it 'PB-B1: reports an unusable number before a number missing on a later field, and missing before duplicates' do
      klass = define_struct('Ordered') do
        required :a, :string, proto: { number: 0 }
        required :b, :string
      end
      expect { descriptor(klass) }.to raise_error(ArgumentError, "Ordered#a: 0 isn't a usable protobuf field number")
      both = define_struct('Both') do
        required :a, :string, proto: { number: 1 }
        required :b, :string, proto: { number: 1 }
        required :c, :string
      end
      expect { descriptor(both) }.to raise_error(ArgumentError, /missing on c\z/)
    end

    it 'PB-B2: refuses a proto: option that is not a Hash' do
      klass = define_struct('Plain') { required :a, :string, proto: 5 }
      expect { descriptor(klass) }.to raise_error(ArgumentError, 'Plain#a: proto: takes a Hash like {number: 1}, got 5')
    end
  end

  describe 'names (PB-B3)' do
    it 'PB-B3: uses the serialize :protobuf names as they are' do
      klass = define_struct('Named') do
        required :trip_no, :integer, proto: { number: 1 }
        required :end_dock, :string, proto: { number: 2 }
        serialize :protobuf, end_dock: 'endDock'
      end
      expect(fields_of(klass).keys).to eq(%w[trip_no endDock])
    end

    it 'PB-B3: keeps field names for a serialization nobody declared' do
      klass = define_struct('Named') do
        required :end_dock, :string, proto: { number: 1 }
        serialize :protobuf, end_dock: 'endDock'
      end
      expect(fields_of(klass, serialization: :other).keys).to eq(['end_dock'])
    end

    it 'PB-B3: refuses a name that is not a protobuf identifier' do
      klass = define_struct('BadName') do
        required :a, :string, proto: { number: 1 }
        serialize :protobuf, a: 'a-b'
      end
      expect { descriptor(klass) }.to raise_error(
        ArgumentError, 'BadName: "a-b" isn\'t a protobuf field name; rename it with `serialize :protobuf, field: "name"`'
      )
    end
  end

  describe 'the file (PB-B6)' do
    it 'PB-B6: names the file, package, syntax and the single message' do
      klass = define_struct('Velo::Station') do
        required :district, :string, proto: { number: 1 }
      end
      file = descriptor(klass)
      expect(file).to be_a(Google::Protobuf::FileDescriptorProto)
      expect(file.name).to eq('field_struct/velo/station.proto')
      expect(file.package).to eq('velo')
      expect(file.syntax).to eq('proto3')
      expect(file.dependency.to_a).to eq([])
      expect(file.message_type.map(&:name)).to eq(['Station'])
    end

    it 'PB-B6: leaves the package empty for a top-level class' do
      klass = define_struct('Top') { required :a, :string, proto: { number: 1 } }
      expect(descriptor(klass).package).to eq('')
    end

    it 'PB-B11: builds a fresh descriptor on every call' do
      klass = define_struct('Fresh') { required :a, :string, proto: { number: 1 } }
      first = descriptor(klass)
      expect(descriptor(klass)).not_to equal(first)
      expect(descriptor(klass)).to eq(first)
    end
  end

  describe 'scalar types (PB-B5, PB-B6)' do
    let(:klass) do
      define_struct('Scalars') do
        required :bin, :binary, proto: { number: 1 }
        required :str, :string, proto: { number: 2 }
        required :ims, :immutable_string, proto: { number: 3 }
        required :uid, :uuid, proto: { number: 4 }
        required :eml, :email, proto: { number: 5 }
        required :url, :url, proto: { number: 6 }
        required :sym, :symbol, enum: %i[a b], proto: { number: 7 }
        required :dec, :big_decimal, proto: { number: 8 }
        required :dat, :date, proto: { number: 9 }
        required :flg, :boolean, proto: { number: 10 }
        required :int, :integer, proto: { number: 11 }
        required :flt, :float, proto: { number: 12 }
      end
    end

    it 'PB-B5: maps each type to its protobuf type' do
      types = fields_of(klass).transform_values(&:type)
      expect(types).to eq(
        'bin' => :TYPE_BYTES, 'str' => :TYPE_STRING, 'ims' => :TYPE_STRING, 'uid' => :TYPE_STRING, 'eml' => :TYPE_STRING,
        'url' => :TYPE_STRING, 'sym' => :TYPE_STRING, 'dec' => :TYPE_STRING, 'dat' => :TYPE_STRING, 'flg' => :TYPE_BOOL,
        'int' => :TYPE_INT64, 'flt' => :TYPE_DOUBLE
      )
    end

    it 'PB-B5: maps :decimal like :big_decimal' do
      klass = define_struct('Dec') { required :d, :decimal, proto: { number: 1 } }
      expect(fields_of(klass)['d'].type).to eq(:TYPE_STRING)
    end

    it 'PB-B6: gives singular scalars explicit presence through synthetic oneofs, numbered in field order' do
      message = descriptor(klass).message_type.first
      expect(message.oneof_decl.map(&:name)).to eq(%w[_bin _str _ims _uid _eml _url _sym _dec _dat _flg _int _flt])
      message.field.each_with_index do |field, index|
        expect([field.label, field.proto3_optional, field.oneof_index]).to eq([:LABEL_OPTIONAL, true, index])
      end
    end

    it 'PB-B6: numbers the field in the descriptor from proto: number' do
      expect(fields_of(klass).values.map(&:number)).to eq((1..12).to_a)
    end
  end

  describe 'arrays of scalars (PB-B5, PB-B6, PB-B7)' do
    let(:klass) do
      define_struct('Arrays') do
        required :name, :string, proto: { number: 1 }
        optional :labels, :array, of: :string, proto: { number: 2 }
        optional :scores, :array, of: :integer, proto: { number: 3 }
        optional :blobs, :array, of: :binary, proto: { number: 4 }
        optional :last, :integer, proto: { number: 5 }
      end
    end

    it 'PB-B7: maps an array to a repeated scalar with no oneof' do
      fields = fields_of(klass)
      expect(fields['labels'].label).to eq(:LABEL_REPEATED)
      expect(fields['labels'].type).to eq(:TYPE_STRING)
      expect(fields['scores'].type).to eq(:TYPE_INT64)
      expect(fields['blobs'].type).to eq(:TYPE_BYTES)
      expect([fields['labels'].proto3_optional, fields['labels'].has_oneof_index?]).to eq([false, false])
    end

    it 'PB-B6: numbers oneofs only across the singular fields' do
      message = descriptor(klass).message_type.first
      expect(message.oneof_decl.map(&:name)).to eq(%w[_name _last])
      expect(fields_of(klass)['last'].oneof_index).to eq(1)
    end
  end

  describe 'refusals (PB-B9, PB-I4)' do
    it 'PB-B9: refuses a union, naming the FieldStruct field name' do
      klass = define_struct('Refused') do
        required :pick, :union, of: %i[string integer], proto: { number: 1 }
      end
      expect { descriptor(klass) }.to raise_error(ArgumentError, "Refused#pick is a union, which field_struct-protobuf can't map yet")
    end

    it 'PB-B9: refuses an array of unions' do
      union = Class.new(FieldStruct::Types::Union)
      klass = define_struct('Refused') do
        required :picks, :array, of: union, proto: { number: 1 }
      end
      expect { descriptor(klass) }.to raise_error(
        ArgumentError, "Refused#picks is an array of unions, which field_struct-protobuf can't map yet"
      )
    end

    it 'PB-B9: refuses an array of arrays' do
      klass = define_struct('Refused') do
        required :grid, :array, of: :array, proto: { number: 1 }
      end
      expect { descriptor(klass) }.to raise_error(
        ArgumentError,
        "Refused#grid is an array of arrays (protobuf has no repeated repeated), which field_struct-protobuf can't map yet"
      )
    end

    it 'PB-B9: refuses a custom type' do
      custom = Class.new(FieldStruct::Types::Base)
      stub_const('MyType', custom)
      klass = define_struct('Refused') do
        required :thing, custom, proto: { number: 1 }
      end
      expect { descriptor(klass) }.to raise_error(
        ArgumentError, "Refused#thing is a MyType (no protobuf mapping), which field_struct-protobuf can't map yet"
      )
    end
  end
end
