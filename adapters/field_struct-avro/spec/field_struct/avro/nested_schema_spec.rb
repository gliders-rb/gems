# frozen_string_literal: true

RSpec.describe 'FieldStruct::Avro.schema for arrays, structs and unions' do
  def parses!(klass, **options)
    Avro::Schema.parse(Oj.dump(FieldStruct::Avro.schema(klass, **options), mode: :compat))
  end

  describe 'arrays (AV-B10, AV-B17)' do
    it 'AV-B10: makes the items nullable' do
      k = define_struct('Arr1') { required :codes, :array, of: :string }
      expect(type_of(k, 'codes')).to eq('type' => 'array', 'items' => %w[null string])
      parses!(k)
    end

    it 'AV-B10: refuses an array of unions at the outer array' do
      k = define_struct('Arr2') { optional :mix, :array, of: :union }
      expect { avro_schema(k) }.to raise_error(
        ArgumentError, "FieldStruct::Avro can't describe Arr2#mix: an array of arrays or unions records no element type"
      )
    end

    it 'AV-B10: refuses an array of arrays one level down' do
      k = define_struct('Arr3') { optional :grid, :array, of: :array }
      expect { avro_schema(k) }.to raise_error(
        ArgumentError, "FieldStruct::Avro can't describe Arr3#grid: an array of arrays or unions records no element type"
      )
    end

    it 'AV-B17: passes the field avro: options to the elements' do
      k = define_struct('Arr4') do
        required :times, :array, of: :time, avro: { timestamp: :millis }
        required :reaches, :array, of: :big_decimal, element: { round: 2 }, avro: { precision: 10 }
        required :kinds, :array, of: :symbol, element: { enum: %i[a b] }, avro: { enum: false }
        required :kinds2, :array, of: :symbol, element: { enum: %i[a b] }
      end
      expect(type_of(k, 'times')['items'].last['logicalType']).to eq('timestamp-millis')
      expect(type_of(k, 'reaches')['items'].last).to include('precision' => 10, 'scale' => 2)
      expect(type_of(k, 'kinds')['items']).to eq(%w[null string])
      expect(type_of(k, 'kinds2')['items'].last).to eq('type' => 'enum', 'name' => 'Arr4_kinds2', 'symbols' => %w[a b])
      parses!(k)
    end

    it 'AV-B17: does not pass type: to the elements (the override replaces the whole field)' do
      k = define_struct('Arr5') { required :codes, :array, of: :string, avro: { type: { type: 'array', items: 'string' } } }
      expect(type_of(k, 'codes')).to eq('type' => 'array', 'items' => 'string')
    end
  end

  describe 'nested structs (AV-B13, AV-B14)' do
    it 'AV-B14: defines a named struct where first used and refers to it by full name afterwards' do
      define_struct('Station::Lamp') { required :sku, :string }
      define_struct('Station::Dispatch') do
        required :first, Station::Lamp
        optional :more, :array, of: Station::Lamp
      end
      schema = avro_schema(Station::Dispatch)
      expect(schema['fields'][0]['type']).to eq(
        'type' => 'record', 'name' => 'Lamp', 'namespace' => 'Station', 'fields' => [{ 'name' => 'sku', 'type' => 'string' }]
      )
      expect(schema['fields'][1]['type']).to eq(['null', { 'type' => 'array', 'items' => ['null', 'Station.Lamp'] }])
      Avro::Schema.parse(Oj.dump(schema, mode: :compat))
    end

    it 'AV-B14: supports recursion through a named struct' do
      define_struct('Tree::Node') do
        required :value, :integer
      end
      Tree::Node.optional :children, :array, of: Tree::Node
      schema = avro_schema(Tree::Node)
      expect(schema['fields'][1]['type']).to eq(['null', { 'type' => 'array', 'items' => ['null', 'Tree.Node'] }])
    end

    it 'AV-B14: names an anonymous struct after the enclosing record and field' do
      inner = Class.new(FieldStruct::Base) { required :at, :integer }
      k = define_struct('Mast') { required :inner, inner }
      type = type_of(k, 'inner')
      expect(type).to eq('type' => 'record', 'name' => 'Mast_inner', 'fields' => [{ 'name' => 'at', 'type' => 'long' }])
    end

    it 'AV-B14: the same anonymous class in a second field is a second record with that field name' do
      inner = Class.new(FieldStruct::Base) { required :at, :integer }
      k = define_struct('Twice') do
        required :a, inner
        required :b, inner
      end
      expect(type_of(k, 'a')['name']).to eq('Twice_a')
      expect(type_of(k, 'b')['name']).to eq('Twice_b')
      parses!(k)
    end

    it 'AV-B14: an anonymous struct inside a namespaced record inherits the namespace' do
      inner = Class.new(FieldStruct::Base) { required :s, :symbol, enum: %i[x y] }
      k = define_struct('Reef::Cove') { required :inner, inner }
      schema = avro_schema(k)
      expect(schema['fields'][0]['type']).not_to have_key('namespace')
      parses!(k)
    end

    it 'AV-B14: refuses a recursive anonymous struct' do
      inner = Class.new(FieldStruct::Base) { required :n, :integer }
      inner.optional :next, inner
      k = define_struct('Rec') { required :root, inner }
      expect { avro_schema(k) }.to raise_error(
        ArgumentError, 'FieldStruct::Avro cannot describe a recursive anonymous struct (at Rec#root.next); assign it to a constant'
      )
    end

    it 'AV-B13: a module-less struct takes the namespace of the record it is first defined in' do
      define_struct('Lamp') { required :sku, :string }
      define_struct('Station::Dispatch') do
        required :one, Lamp
        required :two, Lamp
      end
      schema = avro_schema(Station::Dispatch)
      expect(schema['fields'][0]['type']).to eq('type' => 'record', 'name' => 'Lamp', 'fields' => [{ 'name' => 'sku', 'type' => 'string' }])
      expect(schema['fields'][1]['type']).to eq('Station.Lamp')
      Avro::Schema.parse(Oj.dump(schema, mode: :compat))
    end

    it 'AV-B13: refuses two things that become the same Avro name' do
      define_struct('Lamp') { required :sku, :string }
      define_struct('Signals::Lamp') { required :sku, :string }
      define_struct('Signals::Roster') do
        required :a, Signals::Lamp
        required :b, Lamp
      end
      expect { avro_schema(Signals::Roster) }.to raise_error(
        ArgumentError, 'FieldStruct::Avro: Lamp and Signals::Lamp both become Avro Signals.Lamp; put Lamp in a module'
      )
    end

    it 'AV-B13: refuses a module-less struct read in another namespace' do
      define_struct('Lamp') { required :sku, :string }
      define_struct('Root') do
        required :a, Lamp
        required :b, :array, of: :string
      end
      define_struct('Station::Buoy') { required :line, Lamp }
      Root.required :item, Station::Buoy
      expect { avro_schema(Root) }.to raise_error(
        ArgumentError,
        'FieldStruct::Avro: Lamp has no namespace and is used inside Station::Buoy (Avro namespace Station), ' \
        'where Avro would read Lamp as Station.Lamp; put Lamp in a module'
      )
    end

    it 'AV-B13: an enum and a struct that become one name clash, and the advice is to rename a field' do
      define_struct('Clash3_a') { required :n, :integer }
      k = define_struct('Clash3') do
        required :x, Clash3_a
        required :a, :symbol, enum: %i[p q]
      end
      expect { avro_schema(k) }.to raise_error(
        ArgumentError, 'FieldStruct::Avro: an enum and Clash3_a both become Avro Clash3_a; rename one of the fields'
      )
    end
  end

  describe 'unions (AV-B11, AV-B12)' do
    it 'AV-B11: maps members and puts the long slot first' do
      k = define_struct('U1') do
        required :a, :union, of: %i[float integer]
        required :b, :union, of: %i[string integer boolean]
      end
      expect(type_of(k, 'a')).to eq(%w[long double])
      expect(type_of(k, 'b')).to eq(%w[long string boolean])
      parses!(k)
    end

    it 'AV-B11: refuses members that share a slot' do
      { %i[string uuid] => 'string', %i[string binary] => 'string', %i[string value] => 'string',
        %i[integer time] => 'long' }.each do |of, slot|
        k = define_struct('U2') { required :v, :union, of: of }
        expect { avro_schema(k) }.to raise_error(
          ArgumentError, "FieldStruct::Avro can't describe U2#v: two union members both become Avro #{slot}"
        )
      end
    end

    it 'AV-B11: names anonymous struct members with their index' do
      one = Class.new(FieldStruct::Base) { required :a, :integer }
      two = Class.new(FieldStruct::Base) { required :b, :integer }
      k = define_struct('U3') { required :v, :union, of: [one, two] }
      expect(type_of(k, 'v').map { |t| t['name'] }).to eq(%w[U3_v_0 U3_v_1])
      parses!(k)
    end

    it 'AV-B11: an optional union gets null first' do
      k = define_struct('U4') { optional :v, :union, of: %i[string integer] }
      expect(avro_schema(k)['fields'].first).to eq({ 'name' => 'v', 'type' => %w[null long string], 'default' => nil })
    end

    it 'AV-B12: refuses a struct that Avro would pick for a later one' do
      define_struct('Ones::A') { required :a, :string }
      define_struct('Ones::AB') do
        required :a, :string
        required :b, :string
      end
      k = define_struct('U5') { required :v, :union, of: [Ones::A, Ones::AB] }
      expect { avro_schema(k) }.to raise_error(
        ArgumentError,
        "FieldStruct::Avro can't describe U5#v: a Ones::AB would be written as Ones::A, which Avro picks by shape " \
        '(every required field of Ones::A is in Ones::AB). Give the structs distinct required fields, or put Ones::AB first'
      )
    end

    it 'AV-B12: accepts the narrower struct last' do
      define_struct('Twos::A') { required :a, :string }
      define_struct('Twos::AB') do
        required :a, :string
        required :b, :string
      end
      k = define_struct('U6') { required :v, :union, of: [Twos::AB, Twos::A] }
      expect { avro_schema(k) }.not_to raise_error
    end

    it 'AV-B12: same keys cannot be told apart, and swapping would not help' do
      define_struct('Threes::S') { required :number, :string }
      define_struct('Threes::I') { required :number, :integer }
      k = define_struct('U7') { required :v, :union, of: [Threes::S, Threes::I] }
      expect { avro_schema(k) }.to raise_error(
        ArgumentError, "FieldStruct::Avro can't describe U7#v: a Threes::I would be written as Threes::S, which Avro picks by shape " \
                       '(every required field of Threes::S is in Threes::I). Give the structs distinct required fields'
      )
    end

    it 'AV-B12: a struct with no required fields fits any record' do
      define_struct('Fours::E') { optional :a, :string }
      define_struct('Fours::F') { required :b, :string }
      k = define_struct('U8') { required :v, :union, of: [Fours::E, Fours::F] }
      expect { avro_schema(k) }.to raise_error(
        ArgumentError, /Fours::E has no required fields, so any record fits it\). Give the structs distinct required fields, or put Fours::F/
      )
    end

    it 'AV-B12: a required field with an avro: type override does not count as required' do
      define_struct('Fives::A') { required :a, :string, avro: { type: %w[null string] } }
      define_struct('Fives::B') { required :b, :string }
      k = define_struct('U9') { required :v, :union, of: [Fives::A, Fives::B] }
      expect { avro_schema(k) }.to raise_error(ArgumentError, /Fives::A has no required fields/)
    end
  end

  describe 'validity (AV-B30)' do
    it 'AV-B30: reports a schema the avro gem rejects' do
      k = define_struct('Typo3') { required :a, :string, avro: { type: 'strng' } }
      expect { avro_schema(k) }.to raise_error(
        ArgumentError, /\AFieldStruct::Avro: Typo3 doesn't make a valid Avro schema \(check the avro: options of its fields and nested/
      )
    end

    it 'AV-B31: the x-fs-sensitive property is in the Hash schema, which the parsed schema drops' do
      k = define_struct('Secret') { required :pin, :string, sensitive: true }
      expect(avro_schema(k)['fields'].first['x-fs-sensitive']).to be(true)
      expect(Avro::Schema.parse(Oj.dump(avro_schema(k), mode: :compat)).to_s).not_to include('x-fs-sensitive')
    end
  end
end
