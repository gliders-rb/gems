# frozen_string_literal: true

RSpec.describe FieldStruct::Avro do
  it 'has a version and the accepted timestamp precisions' do
    expect(described_class::VERSION).to eq('1.0.0.pre1')
    expect(described_class::TIMESTAMPS).to eq(%i[micros nanos millis]).and be_frozen
  end

  it 'AV-I8: adds nothing to user classes by being required' do
    klass = define_struct('Plain') { required :id, :integer }
    expect(klass).not_to respond_to(:to_avro_schema)
    expect(klass.new(id: 1)).not_to respond_to(:to_avro)
  end

  describe 'argument checking (AV-B1)' do
    let(:klass) { define_struct('Checked') { required :id, :integer } }

    it 'AV-B1: refuses a non-struct and FieldStruct::Base itself' do
      expect { described_class.schema(String) }
        .to raise_error(ArgumentError, 'FieldStruct::Avro expects a FieldStruct::Base subclass, got String')
      expect { described_class.schema(FieldStruct::Base) }
        .to raise_error(ArgumentError, 'FieldStruct::Avro expects a FieldStruct::Base subclass, got FieldStruct::Base')
      expect { described_class.schema(nil) }.to raise_error(ArgumentError, /got nil/)
      expect { described_class.encode(5) }.to raise_error(ArgumentError, /subclass, got Integer/)
    end

    it 'AV-B1: refuses a timestamp outside TIMESTAMPS in every function that takes one' do
      message = 'FieldStruct::Avro timestamp: must be one of [:micros, :nanos, :millis], got :seconds'
      expect { described_class.schema(klass, timestamp: :seconds) }.to raise_error(ArgumentError, message)
      expect { described_class.to_datum(klass.new(id: 1), timestamp: :seconds) }.to raise_error(ArgumentError, message)
      expect { described_class.encode(klass.new(id: 1), timestamp: :seconds) }.to raise_error(ArgumentError, message)
      expect { described_class.decode(klass, '', timestamp: :seconds) }.to raise_error(ArgumentError, message)
    end

    it 'AV-B1: turns a String serialization into a Symbol and refuses anything else' do
      expect(described_class.schema(klass, serialization: 'avro')).to eq(described_class.schema(klass))
      expect { described_class.schema(klass, serialization: 1) }
        .to raise_error(ArgumentError, 'FieldStruct::Avro expects serialization: to be a Symbol, got 1')
      expect { described_class.from_datum(klass, {}, serialization: 1) }.to raise_error(ArgumentError, /to be a Symbol, got 1/)
    end

    it 'AV-B1: checks decode bytes last' do
      expect { described_class.decode(klass, 5) }
        .to raise_error(ArgumentError, 'FieldStruct::Avro.decode expects the bytes as a String, got Integer')
      expect { described_class.decode(String, 5, timestamp: :seconds) }.to raise_error(ArgumentError, /subclass/)
      expect { described_class.decode(klass, 5, timestamp: :seconds) }.to raise_error(ArgumentError, /timestamp:/)
    end
  end

  describe 'the root class (AV-B2)' do
    it 'AV-B2: refuses an anonymous class' do
      anonymous = Class.new(FieldStruct::Base) { required :id, :integer }
      expect { described_class.schema(anonymous) }
        .to raise_error(ArgumentError, 'FieldStruct::Avro needs a named class for the root record; assign it to a constant')
    end

    it 'AV-B2: refuses a class under an anonymous module' do
      holder = Module.new
      holder.const_set(:Inner, Class.new(FieldStruct::Base) { required :id, :integer })
      expect { described_class.schema(holder::Inner) }.to raise_error(ArgumentError, /needs a named class/)
    end
  end
end

RSpec.describe 'the entry file' do
  it 'AV-I3: raises a LoadError when FieldStruct::Introspection is missing' do
    lib = File.expand_path('../../../lib', __dir__)
    script = "require 'field_struct'; FieldStruct.send(:remove_const, :Introspection); " \
             "begin; load '#{lib}/field_struct/avro.rb'; rescue LoadError => e; puts e.message; end"
    output = IO.popen([RbConfig.ruby, '-I', lib, '-e', script], err: %i[child out], &:read)
    expect(output).to include('needs FieldStruct::Introspection')
  end
end
