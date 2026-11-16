# frozen_string_literal: true

# Registered once, at top level (PB-I7): a cable-car line whose cabins and stop counts are keyed by name.
module Ropeway
  class Cabin < FieldStruct::Base
    required :seats, :integer, proto: { number: 1 }
    optional :inspected, :time, proto: { number: 2 }
  end

  class Line < FieldStruct::Base
    required :name, :string, proto: { number: 1 }
    optional :riders_by_stop, :hash, of: :integer, proto: { number: 2 }
    optional :cabins, :hash, of: Cabin, proto: { number: 3 }
  end
end

RSpec.describe 'FieldStruct::Protobuf maps (PB-B7a)' do
  let(:pb) { FieldStruct::Protobuf }

  it 'prints map<string, T> fields' do
    expect(pb.proto(Ropeway::Line)).to include(
      "  map<string, int64> riders_by_stop = 2;\n",
      "  map<string, .ropeway.Cabin> cabins = 3;\n"
    )
  end

  it 'builds the descriptor protoc builds from the printed text, entry messages included' do
    entries = lambda do |file|
      file.message_type.first.nested_type.map do |entry|
        [entry.name, entry.options&.map_entry, entry.field.map { |f| [f.name, f.number, f.label, f.type, f.type_name] }]
      end
    end
    files = ProtocCheck.texts([Ropeway::Line, Ropeway::Cabin])
    expect(ProtocCheck.compile(files)).to eq(ProtocCheck.ours([Ropeway::Line, Ropeway::Cabin]))

    protoc = Dir.mktmpdir('protoc_map') do |dir|
      files.each do |name, text|
        FileUtils.mkdir_p(File.dirname(File.join(dir, name)))
        File.write(File.join(dir, name), text)
      end
      out = File.join(dir, 'out.pb')
      _, status = Open3.capture2e(RbConfig.ruby, ProtocCheck::PROTOC, "-I#{dir}", "--descriptor_set_out=#{out}", *files.keys)
      raise 'protoc failed' unless status.success?

      Google::Protobuf::FileDescriptorSet.decode(File.binread(out)).file.find { |f| f.name == pb.file_name(Ropeway::Line) }
    end
    expect(entries.call(pb.file_descriptor(Ropeway::Line))).to eq(entries.call(protoc))
  end

  it 'round-trips scalar and struct values, keys as Strings' do
    inspected = Time.utc(2026, 6, 1, 7, 15)
    line = Ropeway::Line.new(name: 'Summit', riders_by_stop: { base: 40, 'ridge' => 12 },
                             cabins: { 'red' => { seats: 8, inspected: inspected } })
    back = pb.decode(Ropeway::Line, pb.encode(line))
    expect(back.riders_by_stop).to eq('base' => 40, 'ridge' => 12)
    expect(back.cabins['red'].seats).to eq(8)
    expect(back.cabins['red'].inspected).to eq(inspected)
  end

  it 'reads an unset map as an empty Hash' do
    back = pb.decode(Ropeway::Line, pb.encode(Ropeway::Line.new(name: 'Valley')))
    expect(back.riders_by_stop).to eq({})
  end

  it 'refuses a nil value at encode, naming the property key' do
    line = Ropeway::Line.new(name: 'Summit', riders_by_stop: { 'base' => nil })
    expect { pb.encode(line) }.to raise_error(ArgumentError, "riders_by_stop: protobuf map values can't be nil")
  end

  it 'refuses array and map values, and maps of unions' do
    lists = define_struct('Ropeway::Timetable') { optional :departures, :hash, of: :array, proto: { number: 1 } }
    mixed = define_struct('Ropeway::Board') { optional :notes, :hash, of: :union, proto: { number: 1 } }
    expect { pb.proto(lists) }.to raise_error(
      ArgumentError,
      "Ropeway::Timetable#departures is a map of arrays or maps (protobuf map values can't be repeated or maps), " \
      "which field_struct-protobuf can't map yet"
    )
    expect { pb.proto(mixed) }.to raise_error(ArgumentError, /\ARopeway::Board#notes is a map of unions, which/)
  end
end
