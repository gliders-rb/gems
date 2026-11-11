# frozen_string_literal: true

RSpec.describe 'FieldStruct::Protobuf encoding and decoding' do
  let(:proto) { FieldStruct::Protobuf }
  let(:station) { DockNet::Station.new(district: 'Harbor', dock: 'B204') }
  let(:uuid) { '3f6f2c3e-1111-4222-8333-444455556666' }
  let(:trip) do
    DockNet::Trip.new(
      id: uuid, fare: '19.9', started: Time.utc(2026, 10, 27, 15, 30, 0, 123_456.789r), spotted: Time.utc(2026, 1, 2, 3, 4, 5),
      grade: :electric, service_day: Date.new(2026, 11, 1), returned: false, legs: 0, charge: 0.5, telemetry: "\xFF\x00".b,
      extras: { 'a' => [1, nil, 'x'] },
      labels: %w[a b], end_dock: station, stops: [station, DockNet::Station.new(district: 'Midtown')],
      pings: [Time.utc(2026, 1, 1), Time.utc(2026, 1, 2)], alert: DockNet::Depot::Alert.new(notify_to: 'a@b.co'),
      logged_at: Time.utc(2026, 6, 1, 12)
    )
  end

  describe 'to_message (PB-B40, PB-B41)' do
    it 'PB-B40: puts each non-nil value under its property key and leaves nil unset' do
      message = proto.to_message(station)
      expect(message).to be_a(proto.message_class(DockNet::Station))
      expect([message.district, message.dock]).to eq(%w[Harbor B204])
      bare = proto.to_message(DockNet::Station.new(district: 'X'))
      expect([bare.has_dock?, bare.dock]).to eq([false, ''])
    end

    it 'PB-B40: uses the serialize :protobuf names' do
      message = proto.to_message(DockNet::Relabeled.new(trip_no: 7, end_dock: 'home'))
      expect(message.endDock).to eq('home')
      expect(message.trip_no).to eq(7)
    end

    it 'PB-B41: converts decimals, dates, symbols and binary to their wire form' do
      message = proto.to_message(trip)
      expect(message.fare).to eq('19.9')
      expect(message.service_day).to eq('2026-11-01')
      expect(message.grade).to eq('electric')
      expect(message.telemetry).to eq("\xFF\x00".b)
      expect(message.telemetry.encoding).to eq(Encoding::BINARY)
      expect([message.returned, message.has_returned?, message.legs, message.has_legs?]).to eq([false, true, 0, true])
    end

    it 'PB-B41: converts times to Timestamps keeping nanoseconds' do
      message = proto.to_message(trip)
      expect(message.started.seconds).to eq(Time.utc(2026, 10, 27, 15, 30).to_i)
      expect(message.started.nanos).to eq(123_456_789)
      expect(message.spotted.seconds).to eq(Time.utc(2026, 1, 2, 3, 4, 5).to_i)
      expect(message.pings.map(&:seconds)).to eq([Time.utc(2026, 1, 1).to_i, Time.utc(2026, 1, 2).to_i])
    end

    it 'PB-B41: converts :value to a Value and nested structs to their own messages' do
      message = proto.to_message(trip)
      expect(message.extras.to_ruby(true)).to eq('a' => [1.0, nil, 'x'])
      expect(message.end_dock).to be_a(proto.message_class(DockNet::Station))
      expect(message.stops.map(&:district)).to eq(%w[Harbor Midtown])
      expect(message.alert.notify_to).to eq('a@b.co')
    end

    it 'PB-B41: takes a symbol-keyed :value hash' do
      message = proto.to_message(DockNet::Trip.new(id: uuid, fare: 1, started: Time.at(0), extras: { a: { b: true } }))
      expect(message.extras.to_ruby(true)).to eq('a' => { 'b' => true })
    end
  end

  describe 'errors on encode (PB-B42)' do
    it 'PB-B42: refuses nil inside an array, naming the property key' do
      struct = DockNet::Trip.new(id: uuid, fare: 1, started: Time.at(0))
      struct.labels = ['a', nil]
      expect { proto.to_message(struct) }.to raise_error(ArgumentError, "labels: protobuf repeated fields can't hold nil")
    end

    it 'PB-B42: refuses :value contents that are not JSON values, naming the class only' do
      [[BigDecimal('1.5'), 'BigDecimal'], [Time.at(0), 'Time'], [{ 1 => 2 }, 'Integer'], [{ 'a' => [:sym] }, 'Symbol']].each do |bad, name|
        struct = DockNet::Trip.new(id: uuid, fare: 1, started: Time.at(0))
        struct.instance_variable_set(:@extras, bad)
        expect { proto.to_message(struct) }.to raise_error(
          ArgumentError, "extras: a :value field holds JSON values (Hash, Array, String, Numeric, true, false, nil); got #{name}"
        )
      end
    end

    it 'PB-B42: lets google-protobuf raise RangeError for an integer past 64 bits' do
      struct = DockNet::Trip.new(id: uuid, fare: 1, started: Time.at(0), legs: 2**70)
      expect { proto.to_message(struct) }.to raise_error(RangeError)
    end

    it 'PB-B42: does not validate field rules and encodes zero values with explicit presence' do
      bytes = proto.encode(DockNet::Station.new(district: ''))
      expect(bytes).to eq("\n\x00".b)
      expect(proto.encode(DockNet::Station.new(district: 'a')).bytes.size).to eq(3)
    end
  end

  describe 'encode (PB-B43, PB-B60)' do
    it 'PB-B43: returns an ASCII-8BIT String equal to the message class encode of to_message' do
      bytes = proto.encode(trip)
      expect(bytes).to be_a(String)
      expect(bytes.encoding).to eq(Encoding::BINARY)
      expect(bytes).to eq(proto.message_class(DockNet::Trip).encode(proto.to_message(trip)))
    end

    it 'PB-B60: bytes are readable through the message class and its accessors' do
      message = proto.message_class(DockNet::Station).decode(proto.encode(station))
      expect([message.district, message.dock]).to eq(%w[Harbor B204])
    end

    it 'PB-I8: bytes are readable by code generated by protoc from the printed .proto' do
      Dir.mktmpdir('protoc_ruby') do |dir|
        files = ProtocCheck.texts([DockNet::Station])
        files.each { |name, text| FileUtils.mkdir_p(File.dirname(File.join(dir, name))) && File.write(File.join(dir, name), text) }
        out = File.join(dir, 'gen')
        FileUtils.mkdir_p(out)
        _, status = Open3.capture2e(RbConfig.ruby, ProtocCheck::PROTOC, "-I#{dir}", "--ruby_out=#{out}", *files.keys)
        expect(status).to be_success
        script = "$LOAD_PATH.unshift(#{out.inspect}); require 'google/protobuf'; require 'field_struct/dock_net/station_pb'; " \
                 "m = DockNet::Station.decode($stdin.binmode.read); print [m.district, m.dock].join('|')"
        read, status = Open3.capture2e(RbConfig.ruby, '-e', script, stdin_data: proto.encode(station))
        expect(status).to be_success, read
        expect(read).to eq('Harbor|B204')
      end
    end
  end

  describe 'decode and from_message (PB-B50..B54)' do
    it 'PB-B54: round-trips every mapped type' do
      decoded = proto.decode(DockNet::Trip, proto.encode(trip))
      expect(decoded).to eq(trip)
    end

    it 'PB-B51: reads a singular field without presence as nil and an unset repeated field as []' do
      decoded = proto.decode(DockNet::Trip, proto.encode(DockNet::Trip.new(id: uuid, fare: 1, started: Time.at(0))))
      observed = [decoded.legs, decoded.returned, decoded.end_dock, decoded.extras, decoded.labels, decoded.stops]
      expect(observed).to eq([nil, nil, nil, nil, [], []])
    end

    it 'PB-B51: keeps explicit zero values apart from unset' do
      zeros = DockNet::Trip.new(id: uuid, fare: 1, started: Time.at(0), legs: 0, returned: false)
      decoded = proto.decode(DockNet::Trip, proto.encode(zeros))
      expect([decoded.legs, decoded.returned]).to eq([0, false])
    end

    it 'PB-B51: from_message builds from a message directly, with field names as keys' do
      struct = proto.from_message(DockNet::Relabeled, proto.to_message(DockNet::Relabeled.new(trip_no: 7, end_dock: 'home')))
      expect(struct).to eq(DockNet::Relabeled.new(trip_no: 7, end_dock: 'home'))
    end

    it 'PB-B52: coerces strings back to decimals, dates and symbols; datetimes to DateTime' do
      decoded = proto.decode(DockNet::Trip, proto.encode(trip))
      expect(decoded.fare).to eq(BigDecimal('19.9'))
      expect(decoded.service_day).to eq(Date.new(2026, 11, 1))
      expect(decoded.grade).to eq(:electric)
      expect(decoded.spotted).to be_a(DateTime)
    end

    it 'PB-B52: returns :value numbers as Floats, keeping nil inside' do
      struct = DockNet::Trip.new(id: uuid, fare: 1, started: Time.at(0), extras: [1, 2, nil])
      expect(proto.decode(DockNet::Trip, proto.encode(struct)).extras).to eq([1.0, 2.0, nil])
    end

    it 'PB-B53: restores an IANA zone offset at that instant, keeping nanoseconds' do
      decoded = proto.decode(DockNet::Trip, proto.encode(trip))
      expect(decoded.started.nsec).to eq(123_456_789)
      expect(decoded.started.utc_offset).to eq(-21_600)
      expect(decoded.started).to eq(trip.started)
    end

    it 'PB-B53: uses the offset in force at that instant (daylight saving)' do
      winter = DockNet::Trip.new(id: uuid, fare: 1, started: Time.utc(2026, 1, 15, 12))
      expect(proto.decode(DockNet::Trip, proto.encode(winter)).started.utc_offset).to eq(-25_200)
    end

    it 'PB-B53: maps UTC to offset 0 and a fixed offset zone to that offset; no zone: gives UTC' do
      decoded = proto.decode(DockNet::Trip, proto.encode(trip))
      expect(decoded.pings.map(&:utc_offset)).to eq([0, 0])
      expect(decoded.logged_at.utc_offset).to eq(19_800)
      expect(decoded.spotted.to_time.utc_offset).to eq(0)
    end

    it 'PB-B50: lets google-protobuf raise its ParseError for malformed bytes' do
      expect { proto.decode(DockNet::Station, "\xFF\xFF\xFF".b) }.to raise_error(Google::Protobuf::ParseError)
    end

    it 'PB-B54: decodes bytes written by the message class directly' do
      bytes = proto.message_class(DockNet::Station).encode(proto.message_class(DockNet::Station).new(district: 'Z'))
      expect(proto.decode(DockNet::Station, bytes)).to eq(DockNet::Station.new(district: 'Z'))
    end
  end
end
