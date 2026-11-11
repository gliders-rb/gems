# frozen_string_literal: true

RSpec.describe FieldStruct::Protobuf do
  it 'PB-S1: has a version' do
    expect(described_class::VERSION).to eq('1.0.0.pre1')
  end

  describe 'name helpers (PB-B4, section 3)' do
    it 'PB-B4: names a module-nested class after its path' do
      klass = define_struct('Velo::Bike')
      expect(described_class.package(klass)).to eq('velo')
      expect(described_class.message_name(klass)).to eq('Bike')
      expect(described_class.full_name(klass)).to eq('.velo.Bike')
      expect(described_class.file_name(klass)).to eq('field_struct/velo/bike.proto')
    end

    it 'PB-B4: gives a top-level class an empty package and a bare full name' do
      klass = define_struct('TopLevel')
      expect(described_class.package(klass)).to eq('')
      expect(described_class.full_name(klass)).to eq('.TopLevel')
      expect(described_class.file_name(klass)).to eq('field_struct/top_level.proto')
    end

    it 'PB-B4: underscores acronyms and digits, keeping the message name as is' do
      klass = define_struct('HTTPApi::V2Beta::XMLThing')
      expect(described_class.package(klass)).to eq('http_api.v2_beta')
      expect(described_class.message_name(klass)).to eq('XMLThing')
      expect(described_class.full_name(klass)).to eq('.http_api.v2_beta.XMLThing')
      expect(described_class.file_name(klass)).to eq('field_struct/http_api/v2_beta/xml_thing.proto')
    end

    it 'PB-B4: underscores DockNet to dock_net' do
      klass = define_struct('DockNet::Depot::Station')
      expect(described_class.package(klass)).to eq('dock_net.depot')
    end
  end

  describe 'argument errors (section 4)' do
    it 'refuses a non-class' do
      expect { described_class.file_descriptor('x') }
        .to raise_error(ArgumentError, 'FieldStruct::Protobuf expects a FieldStruct::Base subclass, got "x"')
    end

    it 'refuses FieldStruct::Base itself and other classes' do
      expect { described_class.file_descriptor(FieldStruct::Base) }
        .to raise_error(ArgumentError, 'FieldStruct::Protobuf expects a FieldStruct::Base subclass, got FieldStruct::Base')
      expect { described_class.proto(String) }
        .to raise_error(ArgumentError, 'FieldStruct::Protobuf expects a FieldStruct::Base subclass, got String')
    end

    it 'refuses an anonymous class and a class under an anonymous module' do
      message = 'FieldStruct::Protobuf needs a named class (assign it to a constant): its message and package are named after it'
      expect { described_class.file_descriptor(Class.new(FieldStruct::Base)) }.to raise_error(ArgumentError, message)
      inner = Class.new(FieldStruct::Base)
      allow(inner).to receive(:name).and_return('#<Module:0x01>::Inner')
      expect { described_class.proto(inner) }.to raise_error(ArgumentError, message)
    end
  end
end
