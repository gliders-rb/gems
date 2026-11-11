# frozen_string_literal: true

RSpec.describe 'FieldStruct::Protobuf.message_class' do
  let(:pool) { Google::Protobuf::DescriptorPool.generated_pool }

  def message_class(klass, **)
    FieldStruct::Protobuf.message_class(klass, **)
  end

  it 'PB-B30: builds a registered message class found in the generated pool by full name' do
    klass = message_class(DockNet::Station)
    expect(klass).to be_a(Class)
    expect(pool.lookup('dock_net.Station').msgclass).to equal(klass)
    expect(klass.new(district: 'Harbor').district).to eq('Harbor')
  end

  it 'PB-B32: returns the same class on every call' do
    expect(message_class(DockNet::Station)).to equal(message_class(DockNet::Station))
  end

  it 'PB-B30: registers the messages of referenced structs first, including through arrays and nested packages' do
    message_class(DockNet::Trip)
    expect(pool.lookup('dock_net.Station')).not_to be_nil
    expect(pool.lookup('dock_net.depot.Alert')).not_to be_nil
    expect(pool.lookup('dock_net.Trip').lookup('prior').submsg_name).to eq('dock_net.Trip')
  end

  it 'PB-B12: registers the descriptor that file_descriptor returns' do
    message_class(DockNet::Trip)
    registered = pool.lookup('dock_net.Trip').file_descriptor.to_proto
    ours = FieldStruct::Protobuf.file_descriptor(DockNet::Trip)
    expect(ProtocCheck.normalize(registered)).to eq(ProtocCheck.normalize(ours))
  end

  it 'PB-B3: names message fields after serialize :protobuf, unconverted' do
    fields = message_class(DockNet::Relabeled).descriptor.map(&:name)
    expect(fields).to eq(%w[trip_no endDock])
  end

  it 'PB-B10: refuses mutually referring structs when registering, naming the chain' do
    expect { message_class(DockNet::Pickup) }.to raise_error(
      ArgumentError,
      'DockNet::Pickup -> DockNet::Dropoff -> DockNet::Pickup: structs that refer to each other would be protobuf files that import ' \
      "each other, which protobuf doesn't allow"
    )
    expect { message_class(DockNet::Dropoff) }.to raise_error(ArgumentError, /\ADockNet::Dropoff -> DockNet::Pickup -> DockNet::Dropoff: /)
    expect(pool.lookup('dock_net.Pickup')).to be_nil
  end

  it 'PB-B31: refuses a second serialization for a registered class' do
    message_class(DockNet::Twin)
    expect { message_class(DockNet::Twin, serialization: :other) }.to raise_error(
      ArgumentError, "DockNet::Twin is already registered with serialization :protobuf; it can't also be registered with :other"
    )
    expect(message_class(DockNet::Twin)).to be_a(Class)
  end

  it 'PB-B31: does not notice fields added after registration; the stale message rejects them' do
    message_class(DockNet::Outdated)
    DockNet::Outdated.optional :c, :string, proto: { number: 3 }
    struct = DockNet::Outdated.new(a: 'x', c: 'y')
    expect { FieldStruct::Protobuf.to_message(struct) }.to raise_error(ArgumentError, /Unknown field name 'c'/)
  end

  it 'PB-B30: validates arguments like the other functions' do
    expect { message_class('x') }.to raise_error(ArgumentError, /expects a FieldStruct::Base subclass/)
  end

  it 'PB-B4: registers nothing for a class under an anonymous module' do
    inner = Class.new(FieldStruct::Base)
    allow(inner).to receive(:name).and_return('#<Module:0x1>::Inner')
    expect { message_class(inner) }.to raise_error(ArgumentError, /needs a named class/)
  end

  it 'PB-B30: raises the numbering errors of PB-B1 without registering anything' do
    klass = define_struct('Unregistered::Bad') { required :a, :string }
    expect { message_class(klass) }.to raise_error(ArgumentError, /Unregistered::Bad: give every field a protobuf field number/)
    expect(pool.lookup('unregistered.Bad')).to be_nil
  end
end
