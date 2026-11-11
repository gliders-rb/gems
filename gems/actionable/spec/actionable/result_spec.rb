# frozen_string_literal: true

RSpec.describe Actionable::Result do
  let(:success) { Actionable::Success }
  let(:failure) { Actionable::Failure }
  let(:skipped) { Actionable::Skipped }

  it 'AC-B#predicates: Success' do
    result = success.new
    expect([result.success?, result.successful?, result.failure?, result.failed?, result.skipped?, result.ok?])
      .to eq([true, true, false, false, false, true])
  end

  it 'AC-B#predicates: Failure' do
    result = failure.new
    expect([result.success?, result.failure?, result.failed?, result.skipped?, result.ok?])
      .to eq([false, true, true, false, false])
  end

  it 'AC-B#predicates: Skipped' do
    result = skipped.new
    expect([result.success?, result.failure?, result.skipped?, result.ok?]).to eq([false, false, true, true])
  end

  it 'AC-B#predicates: the abstract Result answers false to all three, status :failure, ok? true' do
    result = described_class.new(code: :x)
    expect([result.success?, result.failure?, result.skipped?, result.ok?, result.status]).to eq([false, false, false, true, :failure])
  end

  it 'AC-I3: exactly one outcome predicate is true for a concrete result' do
    [success, failure, skipped].each do |klass|
      result = klass.new
      expect([result.success?, result.failure?, result.skipped?].count(true)).to eq(1)
    end
  end

  it 'AC-B#status: status names the outcome' do
    expect([success.new.status, failure.new.status, skipped.new.status]).to eq(%i[success failure skipped])
  end

  it 'AC-B#defaultcodes: default and explicit codes, coerced to Symbol' do
    expect([success.new.code, failure.new.code, skipped.new.code]).to eq(%i[success error skipped])
    expect(success.new(code: :custom).code).to eq(:custom)
    expect(failure.new(code: 'str').code).to eq(:str)
  end

  it 'AC-B#resultdefaults: fresh output, history and metadata per instance; nil message; empty errors' do
    one = failure.new
    two = failure.new
    expect(one.output).to eq({})
    expect(one.output).not_to equal(two.output)
    expect(one.history).not_to equal(two.history)
    expect(one.metadata).not_to equal(two.metadata)
    expect(one.history).to eq([])
    expect(one.message).to be_nil
    expect(one.errors).to be_empty
    expect(skipped.new.metadata).to eq({})
  end

  it 'AC-B#metadataonly: Success has no metadata' do
    expect(success.new).not_to respond_to(:metadata)
    expect { success.new.metadata }.to raise_error(NoMethodError)
  end

  it 'AC-B#inspect: deterministic and field-sorted' do
    expect(failure.new(code: :adrift).inspect)
      .to eq('#<Actionable::Failure code=:adrift errors={} history=[] message=nil metadata={} output={}>')
    expect(failure.new(code: :adrift).to_s).to eq(failure.new(code: :adrift).inspect)
    result = success.new(message: 'hi')
    result.errors.add(:a, 'bad')
    # AC-B#inspect renders each value with its own inspect, and Hash#inspect changed format in Ruby 3.4.
    errors = { a: ['bad'] }.inspect
    expect(result.inspect).to eq("#<Actionable::Success code=:success errors=#{errors} history=[] message=\"hi\" output={}>")
  end

  describe 'to_h' do
    it 'AC-B#toh: Success has no metadata key' do
      expect(success.new(message: 'm').to_h).to eq(code: :success, message: 'm', output: {}, history: [], errors: {})
    end

    it 'AC-B#toh: Failure and Skipped always include metadata' do
      expect(failure.new.to_h).to eq(code: :error, message: nil, output: {}, history: [], errors: {}, metadata: {})
      expect(skipped.new(metadata: { a: 1 }).to_h[:metadata]).to eq(a: 1)
    end

    it 'AC-B#toh: struct output renders as a Hash and a History as its as_json' do
      schema = Class.new(FieldStruct::Base) { required :n, :integer }
      history = Actionable::History.new
      result = success.new(output: schema.new(n: 3), history: history)
      result.errors.add(:n, 'x')
      expect(result.to_h).to include(output: { n: 3 }, history: [], errors: { n: ['x'] })
    end
  end

  describe 'to_api_h' do
    it 'AC-B#toapi: reads the id from a Hash output' do
      expect(success.new(output: { id: 5 }).to_api_h).to eq(index: nil, status: :success, id: 5, errors: {})
    end

    it 'AC-B#toapi: reads the id from a struct output, index and custom id_field' do
      schema = Class.new(FieldStruct::Base) { required :key, :integer }
      result = failure.new(output: schema.new(key: 9))
      result.errors.add(:base, 'bad')
      expect(result.to_api_h(index: 2, id_field: :key)).to eq(index: 2, status: :failure, id: 9, errors: { base: ['bad'] })
    end

    it 'AC-B#toapi: id is nil when the output has no such field' do
      expect(success.new.to_api_h[:id]).to be_nil
      schema = Class.new(FieldStruct::Base) { required :key, :integer }
      expect(success.new(output: schema.new(key: 1)).to_api_h[:id]).to be_nil
    end
  end

  describe 'delegation' do
    let(:schema) { Class.new(FieldStruct::Base) { required :fare, :integer } }

    it 'AC-B#delegation: declared struct fields are readable off the result and respond_to? agrees' do
      result = success.new(output: schema.new(fare: 4))
      expect(result.fare).to eq(4)
      expect(result).to respond_to(:fare)
    end

    it 'AC-B#delegation: undeclared names and Hash output do not delegate' do
      result = success.new(output: schema.new(fare: 4))
      expect { result.other }.to raise_error(NoMethodError)
      expect(result).not_to respond_to(:other)
      expect { success.new(output: { fare: 1 }).fare }.to raise_error(NoMethodError)
      expect { success.new.fare }.to raise_error(NoMethodError)
    end
  end

  describe 'pattern matching' do
    it 'AC-B#patternmatch: deconstructs fields and class patterns work' do
      result = failure.new(code: :adrift, message: 'm')
      matched = case result
                in Actionable::Failure(code:, message:) then [code, message]
                end
      expect(matched).to eq([:adrift, 'm'])
      expect(result.deconstruct_keys(nil).keys).to eq(%i[code message output history metadata])
      hit = case result
            in { errors: } then :hit
            else :miss
            end
      expect(hit).to eq(:miss)
    end
  end

  describe 'absorb_errors_from' do
    it 'AC-B#absorb: copies every message individually and returns self' do
      source = failure.new
      source.errors.add(:a, 'one')
      source.errors.add(:a, 'two')
      source.errors.add(:b, 'three')
      target = failure.new
      target.errors.add(:a, 'zero')
      expect(target.absorb_errors_from(source)).to equal(target)
      expect(target.errors.to_h).to eq(a: %w[zero one two], b: ['three'])
    end

    it 'AC-B#absorb: works with a FieldStruct source' do
      schema = Class.new(FieldStruct::Base) { required :n, :integer }
      expect(failure.new.absorb_errors_from(schema.new).errors[:n]).to eq(['is required'])
    end
  end

  it 'AC-B#fieldsset: output_fields_set is nil for a hand-built result and writable' do
    result = success.new
    expect(result.output_fields_set).to be_nil
    result.output_fields_set = %i[a]
    expect(result.output_fields_set).to eq(%i[a])
  end

  it 'AC-B#equality: class exact plus attributes' do
    expect(success.new).to eq(success.new)
    expect(success.new(code: :x)).not_to eq(failure.new(code: :x))
  end

  it 'AC-B#errorsapi: errors are FieldStruct errors with full messages' do
    result = failure.new(code: :x)
    result.errors.add(:first_name, 'is required')
    expect(result.errors[:first_name]).to eq(['is required'])
    expect(result.errors.full_messages).to eq(['First name is required'])
  end
end
