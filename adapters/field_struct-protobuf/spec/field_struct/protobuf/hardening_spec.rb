# frozen_string_literal: true

RSpec.describe 'FieldStruct::Protobuf hardening' do
  let(:proto) { FieldStruct::Protobuf }

  describe 'argument checks' do
    it 'PB-H1: refuses bytes that are not a String before parsing' do
      expect { proto.decode(DockNet::Station, nil) }
        .to raise_error(ArgumentError, 'FieldStruct::Protobuf.decode expects the bytes as a String, got NilClass')
      expect { proto.decode(DockNet::Station, 12) }.to raise_error(ArgumentError, /got Integer\z/)
    end

    it 'PB-H1: refuses a non-struct for to_message and encode, naming what it got' do
      expect do
        proto.to_message(nil)
      end.to raise_error(ArgumentError, 'FieldStruct::Protobuf expects a FieldStruct::Base subclass, got NilClass')
      expect { proto.encode('x') }.to raise_error(ArgumentError, 'FieldStruct::Protobuf expects a FieldStruct::Base subclass, got String')
    end

    it 'PB-H2: refuses a message of another class in from_message' do
      other = proto.to_message(DockNet::Relabeled.new(trip_no: 1))
      expect { proto.from_message(DockNet::Station, other) }.to raise_error(
        ArgumentError, 'FieldStruct::Protobuf.from_message(DockNet::Station) expects a DockNet::Station message, got dock_net.Relabeled'
      )
      expect { proto.from_message(DockNet::Station, nil) }.to raise_error(ArgumentError, /got NilClass\z/)
    end

    it 'PB-H2: accepts a message of the registered class' do
      message = proto.message_class(DockNet::Station).new(district: 'X')
      expect(proto.from_message(DockNet::Station, message)).to eq(DockNet::Station.new(district: 'X'))
    end
  end

  describe 'names (PB-B3, ambiguity 7)' do
    it 'PB-H3: refuses two fields that map to one message field name' do
      klass = define_struct('Clash') do
        required :a, :string, proto: { number: 1 }
        required :b, :string, proto: { number: 2 }
        serialize :protobuf, b: 'a'
      end
      expect { proto.file_descriptor(klass) }.to raise_error(ArgumentError, 'Clash: fields a, b are both named "a" in the message')
    end
  end

  describe 'error hygiene' do
    it 'PB-H4: never echoes a sensitive value in an encode error' do
      struct = DockNet::Sealed.new(a: 'x', key_code: 'tok-77', seals: %w[sl-9])
      struct.instance_variable_set(:@key_code, BigDecimal('9.99'))
      expect { proto.encode(struct) }.to raise_error(ArgumentError) { |e| expect(e.message).not_to include('9.99') }
      struct.instance_variable_set(:@key_code, { 'k' => 'tok-77', 'bad' => Time.at(0) })
      expect { proto.encode(struct) }.to raise_error(ArgumentError) { |e| expect(e.message).not_to include('tok-77') }
      struct.instance_variable_set(:@key_code, nil)
      struct.instance_variable_set(:@seals, ['sl-9', nil])
      expect { proto.encode(struct) }.to raise_error(ArgumentError, "seals: protobuf repeated fields can't hold nil")
    end

    it 'PB-H4: names the nested class when a referenced struct is badly numbered' do
      bad = define_struct('Hygiene::Bad') { required :a, :string }
      parent = define_struct('Hygiene::Parent') { optional :child, bad, proto: { number: 1 } }
      expect { proto.message_class(parent) }.to raise_error(ArgumentError, /\AHygiene::Bad: give every field a protobuf field number/)
    end

    it 'PB-H4: keeps decode failures about the bytes as google-protobuf raised them' do
      expect { proto.decode(DockNet::Station, "\x0a\xff".b) }.to raise_error(Google::Protobuf::ParseError)
    end
  end

  describe 'concurrency (PB-B30, PB-I7)' do
    it 'PB-H5: builds and registers a message once when many threads ask at the same time' do
      results = Array.new(8) { Thread.new { proto.message_class(DockNet::Rival) } }.map(&:value)
      expect(results.uniq.size).to eq(1)
      expect(results.first).to equal(proto.message_class(DockNet::Rival))
    end
  end
end
