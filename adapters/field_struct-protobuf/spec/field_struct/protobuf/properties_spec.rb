# frozen_string_literal: true

RSpec.describe FieldStruct::Protobuf::Properties do
  def listed(klass) = described_class.for(klass, :protobuf)

  it 'hands out one shared list while the class is unchanged' do
    expect(listed(DockNet::Station)).to equal(listed(DockNet::Station))
    expect(listed(DockNet::Station)).to be_frozen
  end

  it 'does not rebuild the list on a conversion' do
    struct = DockNet::Station.new(district: 'Harbor')
    FieldStruct::Protobuf.to_message(struct)
    expect(FieldStruct::Introspection).not_to receive(:properties)
    FieldStruct::Protobuf.to_message(struct)
  end

  it 'keeps lists apart per serialization' do
    expect(described_class.for(DockNet::Relabeled, :protobuf)).not_to equal(described_class.for(DockNet::Relabeled, :json))
  end

  it 'PB-B31: builds a new list once a field is added, so the stale message still rejects it' do
    klass = define_struct('Dock::Grows') { optional :a, :string, proto: { number: 1 } }
    before = listed(klass)
    FieldStruct::Protobuf.message_class(klass)
    klass.optional :c, :string, proto: { number: 2 }
    expect(listed(klass)).not_to equal(before)
    expect(listed(klass).map { |p| p.field.name }).to eq(%i[a c])
    expect { FieldStruct::Protobuf.to_message(klass.new(a: 'x', c: 'y')) }.to raise_error(ArgumentError, /Unknown field name 'c'/)
  end

  it 'builds a new list when a field is redeclared' do
    klass = define_struct('Dock::Redone') { optional :a, :string, proto: { number: 1 } }
    before = listed(klass)
    klass.optional :a, :integer, proto: { number: 1 }
    expect(listed(klass)).not_to equal(before)
    expect(listed(klass).first.node.type).to be_a(FieldStruct::Types::Integer)
  end
end
