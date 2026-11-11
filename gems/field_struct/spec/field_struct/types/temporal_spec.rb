# frozen_string_literal: true

RSpec.describe 'temporal types (:date, :time, :datetime)', :denver do
  let(:date) { reader(:date) }
  let(:time) { reader(:time) }
  let(:datetime) { reader(:datetime) }

  describe 'registration and FS-B163 / FS-B164 readers' do
    it 'registers the three types in the base registry' do
      expect(FieldStruct.types.lookup(:date)).to equal(FieldStruct::Types::Date)
      expect(FieldStruct.types.lookup(:time)).to equal(FieldStruct::Types::Time)
      expect(FieldStruct.types.lookup(:datetime)).to equal(FieldStruct::Types::DateTime)
    end

    it 'FS-B164: ruby_type' do
      expect(FieldStruct::Types::Date.new.ruby_type).to equal(Date)
      expect(FieldStruct::Types::Time.new.ruby_type).to equal(Time)
      expect(FieldStruct::Types::DateTime.new.ruby_type).to equal(DateTime)
    end

    it 'FS-B163: default_format is nil and presets are readable' do
      [FieldStruct::Types::Date, FieldStruct::Types::Time, FieldStruct::Types::DateTime].each do |type|
        expect(type.default_format).to be_nil
        expect(type.presets).to be_a(Hash)
      end
      expect(FieldStruct::Types::Date.presets.keys).to eq(%i[iso8601 us eu])
      expect(FieldStruct::Types::Time.presets.keys).to eq(%i[iso8601 rfc2822 db])
      expect(FieldStruct::Types::DateTime.presets.keys).to eq(%i[iso8601 rfc2822 db])
      expect(FieldStruct::Types::Date.presets.values_at(:us, :eu)).to eq(['%m/%d/%Y', '%d/%m/%Y'])
      expect(FieldStruct::Types::Time.presets.values_at(:rfc2822, :db)).to eq(['%a, %d %b %Y %H:%M:%S %z', '%Y-%m-%d %H:%M:%S'])
    end

    it 'option_schema lists format, in and (time family) zone' do
      expect(FieldStruct::Types::Date.option_schema.keys).to eq(%i[format in])
      expect(FieldStruct::Types::Time.option_schema.keys).to eq(%i[format in zone])
      expect(FieldStruct::Types::DateTime.option_schema.keys).to eq(%i[format in zone])
      expect(FieldStruct::Types::Date.option_schema[:format][:presets]).to eq(%i[iso8601 us eu])
    end

    it 'FS-B7: stores format: nil when none is declared, and keeps the declared Symbol' do
      expect(build(:date).metadata[:v].options).to eq(format: nil)
      expect(build(:date, format: :us).metadata[:v].options[:format]).to eq(:us)
      expect(build(:time, format: :db, zone: 'UTC').metadata[:v].options).to eq(format: :db, zone: 'UTC')
    end

    it 'FS-B33 / FS-B161: only nil is missing' do
      expect(FieldStruct::Types::Time.new.missing?(nil)).to be(true)
      expect(FieldStruct::Types::Date.new.missing?(Date.today)).to be(false)
    end
  end

  describe 'FS-I16 / FS-B85 / input classes' do
    it 'nil gives nil for all three' do
      expect([date, time, datetime].map { |r| r.call(nil) }).to eq([nil, nil, nil])
    end

    it 'refuses other classes with a class-only message' do
      %i[date time datetime].each do |type|
        expect(errors_of(type, 5)).to eq(['could not be coerced: expected a String, Date, DateTime or Time, got Integer'])
        expect(errors_of(type, :sym).first).to end_with('got Symbol')
        expect(errors_of(type, [1]).first).to end_with('got Array')
      end
    end

    it 'FS-B85 :date from Date, DateTime, Time' do
      d = Date.new(2026, 7, 3)
      expect(date.call(d)).to equal(d)
      expect(date.call(DateTime.new(2026, 7, 3, 23, 30, 0, '-06:00'))).to eq(Date.new(2026, 7, 3))
      expect(date.call(Time.new(2026, 7, 3, 23, 30, 0, '-06:00'))).to eq(Date.new(2026, 7, 3))
      expect(date.call(Time.utc(2026, 7, 3, 1, 0, 0)).class).to equal(Date)
      expect(date.call(DateTime.new(2026, 7, 3, 1)).class).to equal(Date)
    end

    it 'FS-B85 :time from Time, DateTime, Date' do
      t = Time.new(2026, 7, 3, 10, 30, 0, '+02:00')
      expect(time.call(t)).to equal(t)
      from_dt = time.call(DateTime.new(2026, 7, 3, 10, 30, Rational(15, 2), '-06:00'))
      expect([from_dt.hour, from_dt.min, from_dt.sec, from_dt.subsec, from_dt.utc_offset]).to eq([10, 30, 7, Rational(1, 2), -21_600])
      expect(time.call(Date.new(2026, 7, 3))).to eq(Time.local(2026, 7, 3))
      expect(time.call(Date.new(2026, 7, 3)).utc_offset).to eq(-21_600)
    end

    it 'FS-B85 :time rebuilds a Time subclass keeping instant and offset' do
      sub = Class.new(Time)
      value = sub.new(2026, 7, 3, 10, 30, 0, '+02:00')
      result = time.call(value)
      expect(result.class).to equal(Time)
      # Same instant, compared as a Rational: Time#== on a subclass calls to_time, which ActiveSupport 7.2 deprecates.
      expect(result.to_r).to eq(value.to_r)
      expect(result.utc_offset).to eq(7200)
    end

    it 'FS-B85 :datetime from DateTime, Time, Date' do
      dt = DateTime.new(2026, 7, 3, 10, 30, 0, '+02:00')
      expect(datetime.call(dt)).to equal(dt)
      from_time = datetime.call(Time.new(2026, 7, 3, 10, 30, 7.5r, '-06:00'))
      expect(from_time).to be_a(DateTime)
      expect([from_time.hour, from_time.sec, from_time.sec_fraction, from_time.offset]).to eq([10, 7, Rational(1, 2), Rational(-1, 4)])
      expect(datetime.call(Date.new(2026, 7, 3))).to eq(DateTime.new(2026, 7, 3, 0, 0, 0, 0))
      expect(datetime.call(Date.new(2026, 7, 3)).offset).to eq(0)
    end
  end

  describe 'FS-B86 / FS-B87 strings without a format' do
    it 'refuses blank strings and garbage as coercion failures (never "missing")' do
      %i[date time datetime].each do |type|
        expect(errors_of(type, '')).to eq(['could not be coerced: expected a date with a year, a month and a day'])
        expect(errors_of(type, '   ').first).to start_with('could not be coerced')
        expect(errors_of(type, 'not-a-time').first).to start_with('could not be coerced')
      end
    end

    it 'requires year, month and day' do
      %w[10:30 July 12 2026-184 2026-07].each do |text|
        %i[date time datetime].each do |type|
          expect(errors_of(type, text)).to eq(['could not be coerced: expected a date with a year, a month and a day']), "#{type} #{text}"
        end
      end
    end

    it 'refuses days that do not exist' do
      %w[2026-06-31 2026-02-30 2027-02-29].each do |text|
        %i[date time datetime].each do |type|
          expect(errors_of(type, text)).to eq(['could not be coerced: invalid date']), "#{type} #{text}"
        end
      end
      expect(date.call('2028-02-29')).to eq(Date.new(2028, 2, 29))
      expect(date.call('2026-07-03')).to eq(Date.new(2026, 7, 3))
    end

    it 'does not make the stdlib stricter than it is' do
      expect(date.call('v1.2.3')).to eq(Date.new(2001, 2, 3))
    end

    it 'reads zone-less :time in the process zone and zone-less :datetime at offset 0' do
      t = time.call('2026-07-03 10:30:15')
      expect([t.utc_offset, t.hour, t.sec]).to eq([-21_600, 10, 15])
      dt = datetime.call('2026-07-03 10:30:15')
      expect([dt.offset, dt.hour]).to eq([0, 10])
    end

    it 'keeps an offset carried by the string' do
      expect(time.call('2026-07-03 10:30:00 +02:00').utc_offset).to eq(7200)
      expect(datetime.call('2026-07-03T10:30:00-06:00').offset).to eq(Rational(-1, 4))
      expect(time.call('2026-07-03T10:30:00Z')).to be_utc
      expect(time.call('2026-07-03 10:30:00 EST').utc_offset).to eq(-18_000)
    end

    it 'FS-B94: reads two-digit years as 20xx' do
      expect(date.call('03 Jul 26')).to eq(Date.new(2026, 7, 3))
      expect(time.call('03 Jul 26 10:00').year).to eq(2026)
    end

    it 'keeps sub-seconds' do
      expect(time.call('2026-07-03 10:30:00.25').subsec).to eq(Rational(1, 4))
    end
  end

  describe 'FS-B88 / FS-B92 declared formats anchor' do
    it 'parses with a strptime String and refuses trailing characters' do
      d = reader(:date, format: '%Y-%m-%d')
      expect(d.call('2026-07-03')).to eq(Date.new(2026, 7, 3))
      expect(errors_of(:date, '2026-07-03 ', format: '%Y-%m-%d'))
        .to eq(['could not be coerced: does not match format "%Y-%m-%d" — unexpected trailing characters'])
      expect(errors_of(:date, '2026-07-03x', format: '%Y-%m-%d').first).to include('unexpected trailing characters')
      expect(errors_of(:date, ' 2026-07-03', format: '%Y-%m-%d')).to eq(['could not be coerced: does not match format "%Y-%m-%d"'])
      expect(errors_of(:date, 'july', format: '%Y-%m-%d')).to eq(['could not be coerced: does not match format "%Y-%m-%d"'])
    end

    it 'keeps strptime width leniency but refuses days that do not exist' do
      expect(reader(:date, format: '%Y-%m-%d').call('2026-7-3')).to eq(Date.new(2026, 7, 3))
      expect(errors_of(:date, '2026-06-31', format: '%Y-%m-%d')).to eq(['could not be coerced: invalid date'])
      expect(errors_of(:time, '2026-06-31 10:00:00', format: :db)).to eq(['could not be coerced: invalid date'])
      expect(errors_of(:datetime, '2026-02-30 10:00:00', format: :db)).to eq(['could not be coerced: invalid date'])
    end

    it 'presets: us and eu read the same digits differently, as declared' do
      expect(reader(:date, format: :us).call('07/03/2026')).to eq(Date.new(2026, 7, 3))
      expect(reader(:date, format: :eu).call('07/03/2026')).to eq(Date.new(2026, 3, 7))
      expect(build(:date, format: :us).metadata[:v].options[:format]).to eq(:us)
    end

    it ':db has no zone; :rfc2822 carries one' do
      expect(reader(:time, format: :db).call('2026-07-03 10:30:00').utc_offset).to eq(-21_600)
      value = reader(:time, format: :rfc2822).call('Fri, 03 Jul 2026 10:30:00 +0200')
      expect([value.hour, value.utc_offset]).to eq([10, 7200])
      expect(reader(:datetime, format: :db).call('2026-07-03 10:30:00').offset).to eq(0)
      expect(errors_of(:time, 'Fri, 03 Jul 2026 10:30:00', format: :rfc2822).first).to start_with('could not be coerced')
    end

    it 'a partial format is a deliberate choice: today fills in' do
      now = Time.now
      value = reader(:time, format: '%H:%M').call('10:30')
      expect([value.year, value.month, value.day, value.hour, value.min]).to eq([now.year, now.month, now.day, 10, 30])
      date = reader(:date, format: '%m/%d').call('02/03')
      expect([date.year, date.month, date.day]).to eq([now.year, 2, 3])
      expect(reader(:date, format: '%Y').call('2020')).to eq(Date.new(2020, 1, 1))
    end

    it 'reads day-of-year and epoch seconds the way strptime does' do
      expect(reader(:date, format: '%Y %j').call('2026 184')).to eq(Date.new(2026, 7, 3))
      expect(reader(:time, format: '%s').call('1700000000')).to eq(Time.at(1_700_000_000))
      expect(reader(:datetime, format: '%s').call('1700000000')).to eq(DateTime.new(2023, 11, 14, 22, 13, 20, 0))
    end

    it 'handles AM/PM' do
      expect(reader(:time, format: '%Y-%m-%d %I:%M %p').call('2026-07-03 10:30 PM').hour).to eq(22)
    end

    it 'FS-B89: object inputs are never re-parsed whatever the format' do
      t = Time.new(2026, 7, 3, 10, 30, 0, '+02:00')
      expect(reader(:time, format: :db).call(t)).to equal(t)
    end

    it 'FS-B92: a Symbol preset is stored as declared and unknown presets raise' do
      expect { build(:date, format: :zz) }.to raise_error(ArgumentError, 'unknown date format preset :zz. Available: [:iso8601, :us, :eu]')
      expect do
        build(:time, format: :zz)
      end.to raise_error(ArgumentError, 'unknown time format preset :zz. Available: [:iso8601, :rfc2822, :db]')
      expect { build(:datetime, format: :zz) }
        .to raise_error(ArgumentError, 'unknown datetime format preset :zz. Available: [:iso8601, :rfc2822, :db]')
    end

    it 'format: shape errors are the generic message (4.11)' do
      expect { build(:date, format: 5) }.to raise_error(ArgumentError, 'format: on Date expects String or Symbol, got Integer (5)')
      expect { build(:time, format: /x/) }.to raise_error(ArgumentError, 'format: on Time expects String or Symbol, got Regexp (/x/)')
      expect { build(:datetime, format: 5) }.to raise_error(ArgumentError, 'format: on DateTime expects String or Symbol, got Integer (5)')
    end

    it 'a String or Symbol format never adds "is invalid" (FS-B38)' do
      expect(build(:date, format: '%Y-%m-%d').new(v: '2026-07-03')).to be_valid
    end
  end

  describe 'FS-B35 / FS-B93 in:' do
    it 'validates ranges by bounds, including a DateTime inside a Date range' do
      klass = build(:date, in: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))
      expect(klass.new(v: '2026-06-01')).to be_valid
      expect(klass.new(v: '2027-01-01').errors[:v]).to eq(['is invalid'])
      dt = build(:datetime, in: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))
      expect(dt.new(v: DateTime.new(2026, 12, 31, 15))).to be_valid
    end

    it 'accepts an Array for membership' do
      klass = build(:date, in: [Date.new(2026, 1, 1)])
      expect(klass.new(v: '2026-01-01')).to be_valid
      expect(klass.new(v: '2026-01-02')).to be_invalid
    end
  end

  describe 'array elements' do
    it 'passes element: format to each element' do
      klass = Class.new(FieldStruct::Base) { field :ds, :array, of: :date, element: { format: :us } }
      expect(klass.new(ds: ['07/03/2026']).ds).to eq([Date.new(2026, 7, 3)])
      expect(klass.metadata[:ds].options[:element]).to eq(format: :us)
    end
  end
end

# FS-B94 / FS-I6: only meaningful (and only run) in the ActiveSupport lane.
if ENV['FIELD_STRUCT_AS']
  RSpec.describe 'temporal types with ActiveSupport loaded first', :denver do
    it 'is really loaded before the gem' do
      expect(defined?(ActiveSupport::TimeWithZone)).to be_truthy
      expect('2026-07-03'.respond_to?(:to_date)).to be(true)
    end

    it 'keeps instant and offset of a TimeWithZone' do
      zoned = ActiveSupport::TimeZone['Asia/Kolkata'].local(2026, 7, 3, 10, 30)
      time = reader(:time).call(zoned)
      expect(time.class).to equal(Time)
      expect([time.utc_offset, time.hour, time.min]).to eq([19_800, 10, 30])
      expect(reader(:datetime).call(zoned).offset).to eq(Rational(11, 48))
      expect(reader(:date).call(zoned)).to eq(Date.new(2026, 7, 3))
    end

    it 'still refuses garbage and impossible days, and reads two-digit years as 20xx' do
      expect(errors_of(:time, 'not-a-time').first).to start_with('could not be coerced')
      expect(errors_of(:date, '2026-06-31')).to eq(['could not be coerced: invalid date'])
      expect(reader(:date).call('03 Jul 26')).to eq(Date.new(2026, 7, 3))
    end
  end
end
