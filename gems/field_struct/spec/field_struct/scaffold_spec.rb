# frozen_string_literal: true

RSpec.describe FieldStruct::Scaffold do
  def scaffold(input, **opts)
    described_class.from_json(input, **opts)
  end

  def body(source)
    source.lines.map(&:chomp)
  end

  describe 'input handling' do
    it 'FS-B131 treats a Hash as one sample and an Array as the sample set' do
      expect(scaffold({ 'a' => 1 })).to eq(scaffold([{ 'a' => 1 }]))
    end

    it 'FS-B131 parses a JSON String' do
      expect(scaffold('{"a": 1}')).to eq(scaffold({ 'a' => 1 }))
    end

    it 'FS-B131 refuses anything else, naming the class' do
      expect { scaffold('5') }.to raise_error(ArgumentError, 'expected a JSON object or array of objects, got Integer')
      expect { scaffold(nil) }.to raise_error(ArgumentError, 'expected a JSON object or array of objects, got NilClass')
      expect { scaffold('"x"') }.to raise_error(ArgumentError, 'expected a JSON object or array of objects, got String')
    end

    it 'FS-B131 refuses an empty sample set and non-object samples' do
      expect { scaffold([]) }.to raise_error(ArgumentError, 'no samples to scaffold from')
      expect { scaffold([{ 'a' => 1 }, 3]) }.to raise_error(ArgumentError, 'every sample must be a JSON object')
    end
  end

  describe 'output shape' do
    it 'FS-B132 emits a class, two-space field lines, end, and a trailing newline' do
      expect(scaffold({ 'name' => 'x' })).to eq("class Generated < FieldStruct::Base\n  required :name, :string\nend\n")
    end

    it 'FS-B132 honours class_name' do
      expect(scaffold({ 'a' => 1 }, class_name: 'Planting')).to start_with('class Planting < FieldStruct::Base')
    end

    it 'FS-B132 notes a class with no fields' do
      expect(scaffold({})).to eq("class Generated < FieldStruct::Base\n  # (no fields detected in samples)\nend\n")
    end

    it 'FS-B132 emits nested classes before their parent, camelized, joined by a blank line' do
      source = scaffold({ 'shipping_address' => { 'habitat' => 'x' } })
      expect(source).to eq(<<~RUBY)
        class ShippingAddress < FieldStruct::Base
          required :habitat, :string
        end

        class Generated < FieldStruct::Base
          required :shipping_address, ShippingAddress
        end
      RUBY
    end

    it 'FS-B132 names array elements by the singular of the key' do
      source = scaffold({ 'lines' => [{ 'sku' => 'a' }] })
      expect(source).to include('class Line < FieldStruct::Base')
      expect(source).to include('required :lines, :array, of: Line')
    end

    it 'FS-B132 prefixes names that do not start with a capital and numbers repeats from 2' do
      source = scaffold({ 'a' => { 'x' => 1 }, 'b' => { 'item' => { 'y' => 1 } }, 'item' => { 'z' => 1 } })
      expect(source).to include('class A < ')
      expect(source).to include('class Item < ')
      expect(source).to include('class Item2 < ')
      expect(scaffold({ '1st' => { 'x' => 1 } })).to include('class N1st < ')
    end

    it 'FS-B132 does not reopen core classes' do
      expect(scaffold({ 'string' => { 'x' => 1 } })).to include('class String2 < FieldStruct::Base')
    end
  end

  describe 'types' do
    it 'FS-B133 maps JSON kinds to field types' do
      source = scaffold(
        { 'flag' => true, 'n' => 3, 'f' => 1.5, 'name' => 'x', 'only_null' => nil, 'list' => [1, 2], 'empty' => [] }
      )
      expect(source).to include('required :flag, :boolean')
      expect(source).to include('required :n, :integer')
      expect(source).to include('required :f, :float')
      expect(source).to include('required :name, :string')
      expect(source).to include('optional :only_null, :string')
      expect(source).to include('required :list, :array, of: :integer')
      expect(source).to include('optional :empty, :array, of: :value')
    end

    it 'FS-B133 reads integers and floats mixed across samples as float, mixed kinds as value' do
      source = scaffold([{ 'a' => 1, 'b' => 'x' }, { 'a' => 2.5, 'b' => 3 }])
      expect(source).to include('required :a, :float')
      expect(source).to include('required :b, :value')
    end

    it 'FS-B133 keeps numeric-looking strings as :string' do
      expect(scaffold({ 'plot_no' => '00421' })).to include('required :plot_no, :string')
    end
  end

  describe 'presence' do
    it 'FS-B134 is required only when present in every sample and never null or blank' do
      source = scaffold([{ 'a' => 'x', 'b' => 'x', 'c' => 'x', 'd' => 'x' }, { 'a' => 'y', 'b' => nil, 'c' => ' ' }])
      expect(source).to include('required :a, :string')
      expect(source).to include('optional :b, :string')
      expect(source).to include('optional :c, :string')
      expect(source).to include('optional :d, :string')
    end
  end

  describe 'comments' do
    it 'FS-B135 reports present N/M when absent from some samples' do
      expect(scaffold([{ 'a' => 'x' }, { 'b' => 1 }])).to include('optional :a, :string # present 1/2')
    end

    it 'FS-B135 reports empty/null in N/M when some, not all, samples are null or blank' do
      expect(scaffold([{ 'a' => 'x' }, { 'a' => nil }, { 'a' => '' }])).to include('optional :a, :string # empty/null in 2/3')
    end

    it 'FS-B135 flags numeric-looking strings' do
      expect(scaffold([{ 'z' => '00421' }, { 'z' => '10001' }]))
        .to include('required :z, :string # numeric-looking (e.g. "00421") — :integer? or keep :string if an id/code')
      expect(scaffold([{ 'z' => '4.5' }, { 'z' => '10' }])).to include(':big_decimal? or keep')
    end

    it 'FS-B135 suggests an enum for repeated values with at most six distinct' do
      source = scaffold([{ 'p' => 'cc' }, { 'p' => 'ach' }, { 'p' => 'cc' }])
      expect(source).to include('required :p, :string # values: ["cc", "ach"] — enum?')
      expect(scaffold([{ 'p' => 'a' }, { 'p' => 'b' }, { 'p' => 'c' }])).not_to include('enum?')
      many = %w[a b c d e f g a].map { |v| { 'p' => v } }
      expect(scaffold(many)).not_to include('enum?')
    end

    it 'FS-B135 flags unknown types' do
      expect(scaffold({ 'a' => nil })).to include('optional :a, :string # always null/absent in samples — type unknown')
      expect(scaffold({ 'a' => ' ' })).to include('optional :a, :string # always empty in samples — type unknown')
      expect(scaffold({ 'a' => [] })).to include('optional :a, :array, of: :value # empty array(s) in samples — element type unknown')
    end

    it 'FS-B135 flags mixed kinds' do
      expect(scaffold([{ 'a' => 1 }, { 'a' => 'x' }])).to include('required :a, :value # mixed types in samples (integer, string) — review')
    end

    it 'FS-B135 joins parts with semicolons' do
      source = scaffold([{ 'a' => '12' }, { 'a' => nil }, { 'a' => '34' }, { 'b' => 1 }])
      expect(source).to include('optional :a, :string # present 3/4; numeric-looking (e.g. "12")')
    end
  end

  describe 'key sanitizing' do
    it 'FS-B136 snake_cases keys and emits one serialize line after a blank line' do
      source = scaffold({ 'firstName' => 'a', 'last-name' => 'b', 'ok' => 'c' })
      expect(source).to eq(<<~RUBY)
        class Generated < FieldStruct::Base
          required :first_name, :string
          required :last_name, :string
          required :ok, :string

          serialize :json, first_name: "firstName", last_name: "last-name"
        end
      RUBY
    end

    it 'FS-B136 prefixes empty or digit-leading names and suffixes keywords and reserved names' do
      source = scaffold({ '1a' => 1, '' => 2, 'class' => 3, 'errors' => 4, '__x__' => 5 })
      expect(source).to include('required :field_1a, :integer')
      expect(source).to include('required :field_, :integer')
      expect(source).to include('required :class_field, :integer')
      expect(source).to include('required :errors_field, :integer')
      expect(source).to include('required :x, :integer')
    end

    it 'FS-B136 keeps colliding names distinct' do
      source = scaffold({ 'foo-bar' => 1, 'foo_bar' => 2, 'fooBar' => 3 })
      expect(source).to include('required :foo_bar, :integer')
      expect(source).to include('required :foo_bar2, :integer')
      expect(source).to include('required :foo_bar3, :integer')
      expect(source).to include('serialize :json, foo_bar: "foo-bar", foo_bar2: "foo_bar", foo_bar3: "fooBar"')
    end

    it 'FS-B136 emits no serialize line when no name changed' do
      expect(scaffold({ 'a' => 1 })).not_to include('serialize')
    end
  end

  describe 'end to end' do
    let(:payload) { File.read(File.join(__dir__, '..', 'fixtures', 'order_payload.json')) }

    it 'FS-B137 evals into classes whose from_json accepts the example and is valid' do
      source = described_class.from_json(payload, class_name: 'Planting')
      scope = Module.new
      scope.module_eval(source)
      samples = Oj.load(payload, mode: :strict)
      samples.each do |sample|
        order = scope::Planting.from_json(Oj.dump(sample, mode: :strict))
        expect(order).to be_valid, order.errors.to_h.inspect
      end
      first = scope::Planting.from_json(Oj.dump(samples.first, mode: :strict))
      expect(first.customer.first_name).to eq('Ana')
      expect(first.lines.first.sku).to eq('A-1')
      expect(first.class_field).to eq('web')
    end

    it 'FS-B137 generates the documented hints for the fixture' do
      source = described_class.from_json(payload, class_name: 'Planting')
      expect(source).to include('required :order_id, :integer')
      expect(source).to include('required :total, :float')
      expect(source).to include('values: ["cc", "ach"] — enum?')
      expect(source).to include('optional :notes, :string # present 2/3')
      expect(source).to include('serialize :json, order_id: "orderId"')
    end
  end
end
