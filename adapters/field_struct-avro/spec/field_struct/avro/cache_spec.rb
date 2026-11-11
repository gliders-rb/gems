# frozen_string_literal: true

RSpec.describe 'FieldStruct::Avro caching' do
  let(:avro) { FieldStruct::Avro }

  before { avro.clear_cache }

  def builds
    count = 0
    allow(FieldStruct::Avro::SchemaBuilder).to receive(:new).and_wrap_original do |original, *args|
      count += 1
      original.call(*args)
    end
    -> { count }
  end

  describe 'schema (AV-B50, AV-B51)' do
    it 'AV-B50: builds once per class, serialization and timestamp, and returns a fresh deep copy' do
      k = define_struct('C1') do
        required :codes, :array, of: :string
        serialize :kafka, codes: 'labels'
      end
      count = builds
      first = avro.schema(k)
      second = avro.schema(k)
      expect(second).to eq(first)
      expect(second).not_to equal(first)
      expect(second['fields']).not_to equal(first['fields'])
      expect(count.call).to eq(1)
      avro.schema(k, serialization: :kafka)
      avro.schema(k, serialization: 'kafka')
      avro.schema(k, timestamp: :nanos)
      expect(count.call).to eq(3)
    end

    it 'AV-B50: mutating a returned schema changes nothing later' do
      k = define_struct('C2') { required :id, :integer }
      avro.schema(k)['fields'].first['name'] = 'changed'
      avro.schema(k)['fields'] << { 'name' => 'extra' }
      expect(avro.schema(k)['fields'].map { |f| f['name'] }).to eq(['id'])
    end

    it 'AV-B50: the cache never freezes or shares the class option objects' do
      symbols = %i[a b]
      override = +'string'
      other = { 'type' => 'string', 'x' => ['y'] }
      k = define_struct('C3') do
        required :s, :symbol, enum: symbols
        required :t, :string, default: 'dflt', avro: { type: override }
        required :u, :string, avro: { type: other }
      end
      schema = avro.schema(k)
      expect(symbols).not_to be_frozen
      expect(override).not_to be_frozen
      expect(other['x']).not_to be_frozen
      expect(field_of(schema, 'u')['type']['x']).not_to equal(other['x'])
      expect(field_of(schema, 't')['type']).not_to equal(override)
      expect(field_of(schema, 't')['default']).to eq('dflt')
    end

    it 'AV-B51: parses the schema once per entry, for schema, encode and decode' do
      k = define_struct('C4') { required :id, :integer }
      expect(Avro::Schema).to receive(:parse).once.and_call_original
      instance = k.new(id: 1)
      3.times { avro.decode(k, avro.encode(instance)) }
      avro.schema(k)
    end
  end

  describe 'staleness (AV-B52, AV-B53)' do
    it 'AV-B52: notices a field lit or redeclared in the root' do
      k = define_struct('C5') { required :id, :integer }
      expect(avro.schema(k)['fields'].size).to eq(1)
      k.optional :note, :string
      expect(avro.schema(k)['fields'].size).to eq(2)
      k.optional :note, :integer
      expect(type_of(k, 'note')).to eq(%w[null long])
    end

    it 'AV-B52: notices a change in a nested class' do
      define_struct('C6::Inner') { required :a, :integer }
      k = define_struct('C6::Outer') { required :inner, C6::Inner }
      avro.schema(k)
      C6::Inner.required :b, :string
      expect(avro.schema(k)['fields'].first['type']['fields'].map { |f| f['name'] }).to eq(%w[a b])
      avro.encode(k.new(inner: { a: 1, b: 'x' }))
    end

    it 'AV-B52: notices a serialize declared later' do
      k = define_struct('C7') { required :first_name, :string }
      avro.schema(k)
      k.serialize :avro, first_name: 'firstName'
      expect(avro.schema(k)['fields'].first['name']).to eq('firstName')
    end

    it 'AV-B52: notices a renamed class (an anonymous struct assigned to a constant)' do
      inner = Class.new(FieldStruct::Base) { required :a, :integer }
      k = define_struct('C8') { required :inner, inner }
      expect(type_of(k, 'inner')['name']).to eq('C8_inner')
      stub_const('C8Inner', inner)
      expect(type_of(k, 'inner')['name']).to eq('C8Inner')
    end

    it 'AV-B52: a change made while the schema builds leaves the entry stale, not a stale entry looking fresh' do
      k = define_struct('C9') { required :id, :integer }
      changed = false
      allow(FieldStruct::Introspection).to receive(:properties).and_wrap_original do |original, *args, **opts|
        result = original.call(*args, **opts)
        unless changed
          changed = true
          k.optional :late, :string
        end
        result
      end
      expect(avro.schema(k)['fields'].size).to eq(1)
      expect(avro.schema(k)['fields'].size).to eq(2)
    end

    it 'AV-B53: does not notice a field option changed in place' do
      options = { scale: 2 }
      k = define_struct('C10') { required :reach, :big_decimal, avro: options }
      expect(type_of(k, 'reach')['scale']).to eq(2)
      options[:scale] = 3
      expect(type_of(k, 'reach')['scale']).to eq(2)
    end
  end

  describe 'writer schemas (AV-B54, AV-B55)' do
    let(:k) { define_struct('Rd::W1') { required :id, :integer } }
    let(:bytes) { avro.encode(k.new(id: 1)) }
    let(:text) { Oj.dump(avro.schema(k), mode: :compat) }

    it 'AV-B54: parses and checks a writer schema once per distinct text' do
      bytes
      expect(Avro::Schema).to receive(:parse).once.and_call_original
      3.times { expect(avro.decode(k, bytes, writer_schema: text.dup).id).to eq(1) }
    end

    it 'AV-B54: changing the String after the call cannot corrupt an entry' do
      mutable = text.dup
      avro.decode(k, bytes, writer_schema: mutable)
      mutable.replace('{"type":"int"}')
      expect(avro.decode(k, bytes, writer_schema: text).id).to eq(1)
      expect(avro::Cache.writers_count).to eq(1)
    end

    it 'AV-B54: an entry is dropped when its reader entry is replaced' do
      bytes
      avro.decode(k, bytes, writer_schema: text)
      expect(avro::Cache.writers_count).to eq(1)
      k.optional :extra, :string
      avro.schema(k)
      expect(avro::Cache.writers_count).to eq(0)
    end

    it 'AV-B55: holds at most WRITERS_MAX entries and evicts the oldest inserted first' do
      expect(avro::Cache::WRITERS_MAX).to eq(512)
      stub_const('FieldStruct::Avro::Cache::WRITERS_MAX', 3)
      bytes
      texts = Array.new(5) { |i| text.sub('"fields"', %("doc":"v#{i}","fields")) }
      texts.each { |t| avro.decode(k, bytes, writer_schema: t) }
      expect(avro::Cache.writers_count).to eq(3)
      expect(Avro::Schema).to receive(:parse).once.and_call_original
      avro.decode(k, bytes, writer_schema: texts.last)
      avro.decode(k, bytes, writer_schema: texts.first)
    end
  end

  describe 'property lists (AV-B56)' do
    it 'AV-B56: caches the property list per class and serialization and refreshes it on a change' do
      k = define_struct('C11') { required :id, :integer }
      instance = k.new(id: 1)
      avro.to_datum(instance)
      calls = 0
      allow(FieldStruct::Introspection).to receive(:properties).and_wrap_original do |original, *args, **opts|
        calls += 1
        original.call(*args, **opts)
      end
      3.times { avro.to_datum(instance) }
      avro.from_datum(k, { 'id' => 2 })
      expect(calls).to eq(0)
      k.optional :note, :string
      expect(avro.to_datum(k.new(id: 1))).to eq('id' => 1, 'note' => nil)
      expect(calls).to eq(1)
    end

    it 'AV-B56: checks the avro: option shape when the list is first built' do
      k = define_struct('Loose2') { required :v, :string, avro: 'string' }
      msg = %(FieldStruct::Avro (Loose2#v) avro: takes a Hash of options, like avro: {type: 'string'}, got "string")
      expect { avro.to_datum(k.new(v: 'x')) }.to raise_error(ArgumentError, msg)
      expect { avro.from_datum(k, { 'v' => 'x' }) }.to raise_error(ArgumentError, msg)
    end
  end

  describe 'thread safety and clear_cache (AV-B57)' do
    it 'AV-B57: clear_cache returns nil and forgets schemas, property lists and writers' do
      k = define_struct('Rd::C12') { required :id, :integer }
      count = builds
      avro.decode(k, avro.encode(k.new(id: 1)), writer_schema: avro.schema(k))
      expect(avro.clear_cache).to be_nil
      expect(avro::Cache.writers_count).to eq(0)
      avro.schema(k)
      expect(count.call).to eq(2)
    end

    it 'AV-B57: concurrent callers get identical results and the schema builds once' do
      k = define_struct('C13') do
        required :id, :integer
        required :reach, :big_decimal, round: 2
      end
      count = builds
      instance = k.new(id: 7, reach: '1.25')
      gate = Queue.new
      results = Array.new(12) do
        Thread.new do
          gate.pop
          [avro.schema(k), avro.encode(instance), avro.decode(k, avro.encode(instance)).id]
        end
      end
      12.times { gate << :go }
      values = results.map(&:value)
      expect(values.uniq.size).to eq(1)
      expect(count.call).to eq(1)
    end
  end
end
