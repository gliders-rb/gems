# frozen_string_literal: true

RSpec.describe 'zone: on :time and :datetime', :denver do
  describe 'FS-B95 / FS-B96 declaration' do
    it 'accepts UTC, fixed offsets and IANA names' do
      ['UTC', '+00:00', '-06:00', '+23:59', 'America/Denver', 'Etc/UTC', 'America/Argentina/Buenos_Aires'].each do |zone|
        expect { build(:time, zone: zone) }.not_to raise_error
        expect { build(:datetime, zone: zone) }.not_to raise_error
      end
      expect(build(:time, zone: 'America/Denver').metadata[:v].options[:zone]).to eq('America/Denver')
    end

    it 'refuses everything else with the spec message and a hint' do
      generic = 'Use an Area/Location name: abbreviations and aliases are refused ("MST" is a fixed -07:00 in the zone ' \
                'database, not Mountain time with DST), and an offset needs its colon.'
      head = 'zone: on Time expects an IANA name like "America/Denver", "UTC" or a UTC offset like "-06:00", got '
      %w[utc Z -0600 +24:00 MST +06:60 +6:00].each do |zone|
        expect { build(:time, zone: zone) }.to raise_error(ArgumentError, "#{head}#{zone.inspect}. #{generic}")
      end
      rails = 'Rails zone names are an ActiveSupport alias, not IANA names, and exist only when ActiveSupport is loaded: ' \
              'use the name it maps to (ActiveSupport::TimeZone::MAPPING[name]).'
      ['Mountain Time (US & Canada)', 'Eastern Time'].each do |zone|
        expect { build(:time, zone: zone) }.to raise_error(ArgumentError, "#{head}#{zone.inspect}. #{rails}")
      end
      expect { build(:datetime, zone: 'Mars/Olympus') }.to raise_error(
        ArgumentError, 'zone: on DateTime expects an IANA name like "America/Denver", "UTC" or a UTC offset like "-06:00", ' \
                       'got "Mars/Olympus". The zone database has no zone by that name.'
      )
    end

    it 'checks shape first and rejects zone: on :date' do
      expect { build(:time, zone: 5) }.to raise_error(ArgumentError, 'zone: on Time expects String, got Integer (5)')
      expect do
        build(:date, zone: 'UTC')
      end.to raise_error(ArgumentError, 'zone: option does not apply to Date fields. It applies to: Time, DateTime.')
    end

    it 'explains missing zone data' do
      require 'tzinfo'
      allow(TZInfo::Timezone).to receive(:get).and_raise(TZInfo::DataSourceNotFound)
      expect { build(:time, zone: 'America/Denver') }.to raise_error(
        ArgumentError, 'zone: on Time names "America/Denver", but no time zone data was found on this system. ' \
                       'Add the tzinfo-data gem to your Gemfile (or install the OS zoneinfo package).'
      )
    end

    it 'FS-B100: UTC and fixed offsets never load tzinfo' do
      script = "require 'field_struct'; class X < FieldStruct::Base; field :a, :time, zone: '-06:00'; field :b, :time, zone: 'UTC'; end; " \
               "X.new(a: '2026-01-01 10:00'); exit(defined?(TZInfo) ? 1 : 0)"
      expect(system(RbConfig.ruby, '-I', File.expand_path('../../../lib', __dir__), '-e', script)).to be(true)
    end
  end

  describe 'FS-B97 effects on input' do
    it 'reads zone-less strings at a fixed offset or UTC' do
      t = reader(:time, zone: '-06:00').call('2026-10-22 10:00')
      expect([t.hour, t.utc_offset]).to eq([10, -21_600])
      utc = reader(:time, zone: 'UTC').call('2026-10-22 10:00')
      expect(utc).to be_utc
      expect(utc.hour).to eq(10)
      expect(reader(:datetime, zone: '+05:30').call('2026-10-22 10:00').offset).to eq(Rational(11, 48))
      expect(reader(:datetime, zone: 'UTC').call('2026-10-22 10:00').offset).to eq(0)
    end

    it 'uses the offset in force on that date for an IANA name' do
      r = reader(:time, zone: 'America/Denver')
      expect(r.call('2026-07-01 10:00').utc_offset).to eq(-21_600)
      expect(r.call('2026-01-15 10:00').utc_offset).to eq(-25_200)
      expect(r.call('2026-07-01 10:00').hour).to eq(10)
      expect(reader(:datetime, zone: 'America/Denver').call('2026-01-15 10:00').offset).to eq(Rational(-7, 24))
    end

    it 'applies to a format without %z and fills a missing date with today in that zone' do
      r = reader(:time, zone: 'Pacific/Auckland', format: '%H:%M')
      value = r.call('10:30')
      expect([value.hour, value.min, value.utc_offset % 3600]).to eq([10, 30, 0])
      expect(value.utc_offset).to be_between(12 * 3600, 13 * 3600)
      expect(reader(:time, zone: '-06:00', format: :db).call('2026-10-22 10:00:00').utc_offset).to eq(-21_600)
    end

    it 'keeps epoch seconds as the instant, shown at the zone offset at that instant' do
      r = reader(:time, zone: 'America/Denver', format: '%s')
      value = r.call('1783000000')
      expect(value).to eq(Time.at(1_783_000_000))
      expect(value.utc_offset).to eq(-21_600)
      expect(r.call('1768500000').utc_offset).to eq(-25_200)
    end

    it 'never changes an offset the input carries' do
      r = reader(:time, zone: 'America/Denver')
      expect(r.call('2026-07-01 10:00 +02:00').utc_offset).to eq(7200)
      expect(r.call('2026-07-01 10:00 Z')).to be_utc
      expect(r.call('2026-07-01 10:00 EST').utc_offset).to eq(-18_000)
      expect(reader(:time, zone: 'America/Denver', format: :rfc2822).call('Fri, 03 Jul 2026 10:30:00 +0200').utc_offset).to eq(7200)
    end

    it 'refuses a named zone with no fixed offset' do
      message = 'could not be coerced: names a time zone with no fixed offset, which zone: does not override'
      expect(errors_of(:time, '2026-07-01 10:00 XYZ', zone: 'UTC')).to eq([message])
      expect(errors_of(:datetime, '2026-07-01 10:00 America/Denver', zone: 'America/Denver')).to eq([message])
    end

    it 'keeps instant and offset of Time, DateTime and Date inputs' do
      r = reader(:time, zone: 'America/Denver')
      t = Time.new(2026, 7, 1, 10, 0, 0, '+02:00')
      expect(r.call(t)).to equal(t)
      dt = DateTime.new(2026, 7, 1, 10, 0, 0, '+02:00')
      expect(r.call(dt).utc_offset).to eq(7200)
      expect(reader(:datetime, zone: 'America/Denver').call(dt)).to equal(dt)
    end

    it 'turns a Date into midnight at the zone offset on that day' do
      expect(reader(:time, zone: 'America/Denver').call(Date.new(2026, 7, 1))).to eq(Time.new(2026, 7, 1, 0, 0, 0, '-06:00'))
      expect(reader(:time, zone: 'America/Denver').call(Date.new(2026, 1, 1)).utc_offset).to eq(-25_200)
      expect(reader(:time, zone: 'UTC').call(Date.new(2026, 7, 1))).to be_utc
      expect(reader(:datetime, zone: '+02:00').call(Date.new(2026, 7, 1)).offset).to eq(Rational(1, 12))
      expect(reader(:datetime, zone: 'America/Denver').call(Date.new(2026, 7, 1)).hour).to eq(0)
    end

    it 'uses the first moment of the day when the zone skips midnight' do
      value = reader(:time, zone: 'America/Sao_Paulo').call(Date.new(2018, 11, 4))
      expect([value.hour, value.min, value.utc_offset]).to eq([1, 0, -7200])
    end

    it 'refuses an Integer (no epoch guessing)' do
      expect(errors_of(:time, 1_700_000_000, zone: 'UTC').first).to include('expected a String, Date, DateTime or Time, got Integer')
    end
  end

  describe 'FS-B98 daylight-saving edges' do
    it 'refuses a skipped wall-clock time' do
      expect(errors_of(:time, '2026-03-08 02:30', zone: 'America/Denver'))
        .to eq(['could not be coerced: names a local time that does not exist in America/Denver (skipped by a daylight-saving change)'])
      expect(errors_of(:datetime, '2026-03-08 02:30', zone: 'America/Denver').first).to include('does not exist in America/Denver')
    end

    it 'reads a repeated time at the daylight (earlier) offset' do
      expect(reader(:time, zone: 'America/Denver').call('2026-11-01 01:30').utc_offset).to eq(-21_600)
      expect(reader(:datetime, zone: 'America/Denver').call('2026-11-01 01:30').offset).to eq(Rational(-1, 4))
      expect(reader(:time, zone: 'America/Denver').call('2026-11-01 02:30').utc_offset).to eq(-25_200)
    end
  end

  describe 'FS-B99' do
    it 'returns a plain Time that does not carry the zone' do
      expect(reader(:time, zone: 'America/Denver').call('2026-07-01 10:00').zone).to be_nil
    end

    it 'has no effect with format: :iso8601' do
      expect(reader(:time, zone: 'America/Denver', format: :iso8601).call('2026-07-01T10:00:00+02:00').utc_offset).to eq(7200)
    end
  end

  describe 'time-of-day validity when a zone builds the value' do
    it 'refuses out-of-range times' do
      expect(errors_of(:time, '2026-07-01 25:00', zone: 'UTC').first).to start_with('could not be coerced')
    end
  end
end
