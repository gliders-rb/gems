# frozen_string_literal: true

require 'stringio'

module LegibilityFixtures
  class Bed < FieldStruct::Base
    optional :habitat, :string
  end
end

RSpec.describe 'Field and Metadata legibility' do
  let(:bed) { LegibilityFixtures::Bed }

  def pp_to_s(object)
    out = StringIO.new
    PP.pp(object, out)
    out.string
  end

  describe 'Field#inspect', :aggregate_failures do
    it 'FS-B119 prints name, type, flags and options in order' do
      klass = Class.new(FieldStruct::Base) do
        optional :level, :string, enum: %w[beginner pro]
        optional :tags, :array, of: :string
      end
      expect(klass.metadata[:level].inspect).to eq('#<FieldStruct::Field :level String enum=["beginner", "pro"]>')
      expect(klass.metadata[:tags].inspect).to eq('#<FieldStruct::Field :tags Array of_type=String>')
    end

    it 'FS-B119 shows required, sensitive, default, policy, description and rbs_type parts in order' do
      klass = Class.new(FieldStruct::Base) do
        required :n, :integer, sensitive: true, default: 3, coercion_policy: :raise, description: 'Count', rbs_type: '::Integer'
      end
      expect(klass.metadata[:n].inspect).to eq(
        '#<FieldStruct::Field :n Integer required sensitive default=3 coercion_policy=:raise description="Count" rbs_type="::Integer">'
      )
    end

    it 'FS-B119 omits default= for nil and prints false/0 defaults' do
      klass = Class.new(FieldStruct::Base) do
        optional :a, :boolean, default: false
        optional :b, :integer
      end
      expect(klass.metadata[:a].inspect).to include('default=false')
      expect(klass.metadata[:b].inspect).not_to include('default')
    end

    it 'FS-B119 names nested fields and arrays of nested structs' do
      klass = Class.new(FieldStruct::Base)
      klass.field :border, LegibilityFixtures::Bed
      klass.field :homes, :array, of: LegibilityFixtures::Bed
      klass.field :anon, Class.new(FieldStruct::Base)
      expect(klass.metadata[:border].inspect).to eq('#<FieldStruct::Field :border Nested(Bed)>')
      expect(klass.metadata[:homes].inspect).to eq('#<FieldStruct::Field :homes Array of_type=Nested(Bed)>')
      expect(klass.metadata[:anon].inspect).to eq('#<FieldStruct::Field :anon Nested(AnonymousFieldStruct)>')
    end

    it 'FS-B119 names a union by its members' do
      klass = Class.new(FieldStruct::Base) { optional :u, :union, of: %i[string integer] }
      expect(klass.metadata[:u].inspect).to eq('#<FieldStruct::Field :u Union(String | Integer)>')
    end

    it 'FS-B119 renders Regexp, Range, Hash and element options' do
      klass = Class.new(FieldStruct::Base) do
        optional :code, :string, format: /\Aa/
        optional :n, :integer, in: 1..5
        optional :ids, :array, of: :integer, element: { strict: true, base: 16 }
        optional :flag, :boolean, values: :numeric
        optional :on, :date
      end
      expect(klass.metadata[:code].inspect).to eq('#<FieldStruct::Field :code String format=/\Aa/>')
      expect(klass.metadata[:n].inspect).to eq('#<FieldStruct::Field :n Integer in=1..5>')
      expect(klass.metadata[:ids].inspect).to eq('#<FieldStruct::Field :ids Array of_type=Integer element={strict: true, base: 16}>')
      expect(klass.metadata[:flag].inspect).to eq('#<FieldStruct::Field :flag Boolean values={truthy: ["1"], falsy: ["0"]}>')
      expect(klass.metadata[:on].inspect).to eq('#<FieldStruct::Field :on Date format=nil>')
    end

    it 'FS-B119 pretty_print is the same text on one line' do
      klass = Class.new(FieldStruct::Base) { required :a, :string }
      field = klass.metadata[:a]
      expect(pp_to_s(field)).to eq("#{field.inspect}\n")
    end

    it 'FS-B118 follows the alias prefix' do
      klass = Class.new(FieldStruct::Base) { required :a, :string }
      allow(FieldStruct).to receive(:inspect_namespace).and_return('FS')
      expect(klass.metadata[:a].inspect).to eq('#<FS::Field :a String required>')
    end
  end

  describe 'Metadata#pretty_print' do
    it 'FS-B120 fans out one field per line' do
      klass = Class.new(FieldStruct::Base) do
        required :a, :string
        optional :b, :integer
        serialize :json, a: 'A'
      end
      expect(pp_to_s(klass.metadata)).to eq(<<~TEXT)
        #<FieldStruct::Metadata
          #<FieldStruct::Field :a String required>
          #<FieldStruct::Field :b Integer>
          serializations=[:json]
        >
      TEXT
    end

    it 'FS-B120 omits the serializations line when none and prints inspect when empty' do
      klass = Class.new(FieldStruct::Base) { required :a, :string }
      expect(pp_to_s(klass.metadata)).to eq("#<FieldStruct::Metadata\n  #<FieldStruct::Field :a String required>\n>\n")
      expect(pp_to_s(FieldStruct::Metadata.new)).to eq("#<FieldStruct::Metadata empty>\n")
    end
  end

  describe 'Metadata#to_h' do
    it 'FS-B121 gives the schema view with keys in order' do
      klass = Class.new(FieldStruct::Base) do
        required :name, :string, description: 'Full name', default: -> { 'x' }
        optional :flag, :boolean
        optional :tags, :array, of: :integer, element: { strict: true, base: 16 }
      end
      schema = klass.metadata.to_h
      expect(schema.keys).to eq(%i[name flag tags])
      expect(schema[:name].keys).to eq(%i[type ruby_type required default options description])
      expect(schema[:name]).to include(type: 'String', ruby_type: 'String', required: true, default: '<callable>', description: 'Full name')
      expect(schema[:flag]).to include(type: 'Boolean', ruby_type: 'TrueClass | FalseClass', required: false, default: nil,
                                       description: nil)
      expect(schema[:tags][:options]).to eq(of_type: 'Integer', element: { strict: true, base: 16 })
    end

    it 'FS-B121 appends rbs_type then sensitive only when set' do
      klass = Class.new(FieldStruct::Base) do
        optional :a, :string, rbs_type: '::String', sensitive: true
        optional :b, :string, sensitive: true
        optional :c, :string
      end
      schema = klass.metadata.to_h
      expect(schema[:a].keys.last(2)).to eq(%i[rbs_type sensitive])
      expect(schema[:a][:sensitive]).to be(true)
      expect(schema[:b].keys.last).to eq(:sensitive)
      expect(schema[:c].keys).to eq(%i[type ruby_type required default options description])
    end

    it 'FS-B121 names nested classes in ruby_type and elements as Nested' do
      klass = Class.new(FieldStruct::Base)
      klass.field :border, bed
      klass.field :homes, :array, of: bed
      schema = klass.metadata.to_h
      expect(schema[:border]).to include(type: 'Nested', ruby_type: 'LegibilityFixtures::Bed')
      expect(schema[:homes][:options]).to eq(of_type: 'Nested')
      expect(schema[:homes][:ruby_type]).to eq('Array')
    end

    it 'FS-B121 makes values primitive: regexps, ranges and symbols stay, classes become names' do
      klass = Class.new(FieldStruct::Base) do
        optional :code, :string, format: /x/, default: :sym
        optional :n, :integer, in: 1..3
      end
      schema = klass.metadata.to_h
      expect(schema[:code][:options]).to eq(format: /x/)
      expect(schema[:code][:default]).to eq(:sym)
      expect(schema[:n][:options]).to eq(in: 1..3)
    end

    it 'FS-B121 keeps the block form of Enumerable#to_h' do
      klass = Class.new(FieldStruct::Base) { required :a, :string }
      expect(klass.metadata.to_h { |f| [f.name, 1] }).to eq(a: 1)
    end

    it 'FS-B121 does not appear in attributes' do
      klass = Class.new(FieldStruct::Base) { required :a, :string, description: 'd' }
      expect(klass.new(a: 'x').attributes).to eq(a: 'x')
    end
  end

  describe 'describe' do
    it 'FS-B122 says (no fields) for empty metadata' do
      expect(FieldStruct::Metadata.new.describe).to eq('(no fields)')
    end

    it 'FS-B122 renders the date example' do
      klass = Class.new(FieldStruct::Base) { required :on, :date, format: :iso8601 }
      expect(klass.metadata.describe).to eq(
        '  on (Date, required) — format: :iso8601 — accepts format (String | Symbol; presets: iso8601, us, eu), in (Array | Range)'
      )
    end

    it 'FS-B122 renders a description segment before options' do
      klass = Class.new(FieldStruct::Base) { required :name, :string, description: 'Full legal name' }
      expect(klass.metadata.describe).to eq(
        '  name (String, required) — "Full legal name" — accepts format (Regexp | Symbol), enum (Array), strict (TrueClass | FalseClass)'
      )
    end

    it 'FS-B153 renders a field without a description as it would without the segment' do
      klass = Class.new(FieldStruct::Base) { optional :name, :symbol }
      expect(klass.metadata.describe).to eq('  name (Symbol, optional) — accepts enum (Array)')
    end

    it 'FS-B122 renders arrays with required options and the element line' do
      klass = Class.new(FieldStruct::Base) { optional :tags, :array, of: :string }
      expect(klass.metadata.describe).to eq(
        '  tags (Array, optional) — of_type: String — accepts of* (Symbol | String | Class), element (Hash) — ' \
        'element accepts format, enum, strict'
      )
    end

    it 'FS-B154 labels a nested field with the struct class last segment' do
      klass = Class.new(FieldStruct::Base) { optional :border, LegibilityFixtures::Bed }
      expect(klass.metadata.describe).to eq('  border (Bed, optional)')
    end

    it 'FS-B154 keeps Nested for an anonymous struct and shows description and sensitive' do
      anon = Class.new(FieldStruct::Base)
      klass = Class.new(FieldStruct::Base) do
        required :a, anon, sensitive: true, description: 'Where it goes'
      end
      expect(klass.metadata.describe).to eq('  a (Nested, required, sensitive) — "Where it goes"')
    end

    it 'FS-B154 labels a class under an anonymous module by its last segment' do
      mod = Module.new
      mod.const_set(:Addr, Class.new(FieldStruct::Base))
      klass = Class.new(FieldStruct::Base)
      klass.field :a, mod::Addr, required: true, sensitive: true, description: 'Where it goes'
      expect(klass.metadata.describe).to eq('  a (Addr, required, sensitive) — "Where it goes"')
    end

    it 'FS-B122 keeps Array as the label for arrays of structs' do
      klass = Class.new(FieldStruct::Base) { optional :homes, :array, of: LegibilityFixtures::Bed }
      expect(klass.metadata.describe).to start_with('  homes (Array, optional) — of_type: Nested(Bed)')
    end

    it 'FS-B122 escapes description text with String#inspect' do
      klass = Class.new(FieldStruct::Base) { optional :a, :value, description: %(say "hi"\n) }
      expect(klass.metadata.describe).to eq(%(  a (Value, optional) — "say \\"hi\\"\\n"))
    end

    it 'FS-B122 joins lines with newlines' do
      klass = Class.new(FieldStruct::Base) do
        optional :a, :value
        optional :b, :value
      end
      expect(klass.metadata.describe.lines.size).to eq(2)
    end

    it 'FS-B122 Base.describe adds a class header, anonymous or named' do
      expect(bed.describe).to start_with("LegibilityFixtures::Bed\n  habitat (String, optional)")
      expect(Class.new(FieldStruct::Base).describe).to eq("AnonymousFieldStruct\n(no fields)")
    end
  end
end
