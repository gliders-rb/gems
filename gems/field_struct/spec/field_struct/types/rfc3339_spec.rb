# frozen_string_literal: true

RSpec.describe 'FS-B90 / FS-B91 format: :iso8601 (RFC 3339)' do
  describe 'FS-B90 timestamps' do
    let(:time) { reader(:time, format: :iso8601) }
    let(:datetime) { reader(:datetime, format: :iso8601) }

    it 'accepts offsets, Z, fractions and the old colon-less offset' do
      expect(time.call('2026-07-03T10:30:00-06:00')).to eq(Time.utc(2026, 7, 3, 16, 30))
      expect(time.call('2026-07-03T10:30:00-06:00').utc_offset).to eq(-21_600)
      expect(time.call('2026-07-03t10:30:00z')).to eq(Time.utc(2026, 7, 3, 10, 30))
      expect(time.call('2026-07-03T10:30:00.123456Z').subsec).to eq(Rational(123_456, 1_000_000))
      expect(time.call('2026-07-03T10:30:00+0000')).to eq(Time.utc(2026, 7, 3, 10, 30))
      expect(time.call('2026-07-03T10:30:00.5+02:00').utc_offset).to eq(7200)
    end

    it 'keeps sub-second digits exactly, however many there are' do
      expect(time.call('2026-07-03T10:30:00.1234567891234Z').subsec).to eq(Rational(1_234_567_891_234, 10**13))
    end

    it 'gives datetime the same instants and offsets' do
      value = datetime.call('2026-07-03T10:30:00-06:00')
      expect(value).to be_a(DateTime)
      expect(value.offset).to eq(Rational(-6, 24))
      expect(value.hour).to eq(10)
    end

    it 'FS-B165: Z is a fixed +00:00 offset, not UTC, and still the same instant' do
      value = time.call('2026-07-03T10:30:00Z')
      expect(value.utc_offset).to eq(0)
      expect(value).not_to be_utc
      expect(value).to eq(Time.utc(2026, 7, 3, 10, 30))
      expect(reader(:time, format: :iso8601, zone: 'UTC').call('2026-07-03T10:30:00Z')).not_to be_utc
    end

    [
      '2026-7-3', '+2026-07-03', '20261-07-03', '20260703', '2026-W27-5', '2026-184', '2026-07-03', '10:30:00',
      '2026-07-03 10:30:00Z', '2026-07-03T10:30Z', '2026-07-03T10:30:00', '2026-07-03T10:30:00Z ', ' 2026-07-03T10:30:00Z',
      '2026-07-03T10:30:00Zjunk', '2026-07-03T24:00:00Z', '2026-07-03T10:60:00Z', '2026-07-03T10:30:60Z',
      '2026-07-03T10:30:00+25:00', '2026-07-03T10:30:00+01:60', '2026-02-30T10:30:00Z', '2026-07-03T10:30:00Z
'
    ].each do |text|
      it "refuses #{text.inspect} for both :time and :datetime" do
        expect(errors_of(:time, text, format: :iso8601).first).to start_with('could not be coerced: ')
        expect(errors_of(:datetime, text, format: :iso8601).first).to start_with('could not be coerced: ')
      end
    end

    it 'uses the documented failure messages' do
      message = lambda do |input|
        errors_of(:time, input, format: :iso8601).first.delete_prefix('could not be coerced: ')
      end
      expect(message.call('nonsense')).to eq('expected an RFC 3339 timestamp')
      expect(message.call('2026-07-03T25:00:00Z')).to eq('invalid time of day')
      expect(message.call('2026-07-03T10:30:00+25:00')).to eq('invalid UTC offset')
      expect(message.call('2026-02-30T10:30:00Z')).to eq('invalid date')
    end
  end

  describe 'FS-B90 dates' do
    let(:date) { reader(:date, format: :iso8601) }

    it 'accepts YYYY-MM-DD and refuses timestamps and impossible days' do
      expect(date.call('2026-07-03')).to eq(Date.new(2026, 7, 3))
      expect(errors_of(:date, '2026-07-03T10:30:00Z', format: :iso8601)).to eq(['could not be coerced: expected an RFC 3339 date'])
      expect(errors_of(:date, '2026-02-30', format: :iso8601)).to eq(['could not be coerced: invalid date'])
      expect(errors_of(:date, '2026-07-3', format: :iso8601).first).to start_with('could not be coerced')
      expect(date.call('2028-02-29')).to eq(Date.new(2028, 2, 29))
    end
  end

  describe 'FS-B91 rendering' do
    def render(type, input, format: :iso8601)
      instance = FieldStruct.types.lookup(type).new
      instance.render(instance.coerce(input, format: format), format: format)
    end

    it 'renders Z for offset 0, otherwise +-hh:mm, never +0000' do
      expect(render(:time, '2026-07-03T10:30:00+00:00')).to eq('2026-07-03T10:30:00Z')
      expect(render(:time, '2026-07-03T10:30:00-06:00')).to eq('2026-07-03T10:30:00-06:00')
      expect(render(:time, '2026-07-03T10:30:00+0530')).to eq('2026-07-03T10:30:00+05:30')
    end

    it 'adds a trimmed fraction only when sub-seconds are non-zero, to nanosecond precision' do
      expect(render(:time, '2026-07-03T10:30:00.500Z')).to eq('2026-07-03T10:30:00.5Z')
      expect(render(:time, '2026-07-03T10:30:00.123456789123Z')).to eq('2026-07-03T10:30:00.123456789Z')
      expect(render(:time, '2026-07-03T10:30:00.000Z')).to eq('2026-07-03T10:30:00Z')
    end

    it 'renders dates as YYYY-MM-DD and keeps instants across offsets' do
      expect(render(:date, '2026-07-03')).to eq('2026-07-03')
      expect(render(:datetime, '2026-07-03T10:30:00-06:00')).to eq('2026-07-03T10:30:00-06:00')
    end
  end
end
